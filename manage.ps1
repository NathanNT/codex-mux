[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('doctor', 'enable', 'status', 'disable')]
    [string]$Action = 'status',

    [string]$CodexHome
)

$ErrorActionPreference = 'Stop'
$kitRoot = $PSScriptRoot
$codexHomeSource = 'parameter'
if ([string]::IsNullOrWhiteSpace($CodexHome)) {
    $configuredCodexHome = [Environment]::GetEnvironmentVariable('CODEX_HOME')
    if (-not [string]::IsNullOrWhiteSpace($configuredCodexHome)) {
        $CodexHome = $configuredCodexHome
        $codexHomeSource = 'CODEX_HOME environment variable'
    } else {
        $userProfileDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
        $CodexHome = Join-Path $userProfileDirectory '.codex'
        $codexHomeSource = 'default user profile .codex'
    }
}
$CodexHome = [IO.Path]::GetFullPath($CodexHome)
$markerStart = '# BEGIN codex-external-subagents-kit'
$markerEnd = '# END codex-external-subagents-kit'
$binaryPath = Join-Path $kitRoot 'bin\codex-external-subagents.exe'
$agentPath = Join-Path $kitRoot 'agents\deepseek_test.toml'
$configPath = Join-Path $CodexHome 'config.toml'
$statePath = Join-Path $kitRoot 'state\manifest.json'
$vscodeSettingsPath = Join-Path (Split-Path $CodexHome -Parent) 'vscode\User\settings.json'

function Get-Hash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Remove-ManagedInsertion(
    [string]$Path,
    [long]$Offset,
    [string]$InsertedText,
    [string]$Label
) {
    $text = [IO.File]::ReadAllText($Path)
    if ($Offset -lt 0 -or $Offset + $InsertedText.Length -gt $text.Length) {
        throw "$Label changed outside the managed insertion; refusing an unsafe restore: $Path"
    }
    if ($text.Substring([int]$Offset, $InsertedText.Length) -cne $InsertedText) {
        throw "$Label overlaps edits made after enable; refusing to overwrite them: $Path"
    }
    $restored = $text.Remove([int]$Offset, $InsertedText.Length)
    [IO.File]::WriteAllText($Path, $restored, [Text.UTF8Encoding]::new($false))
}

function Get-ProviderBlock {
    $escapedAgentPath = $agentPath.Replace('\', '\\').Replace('"', '\"')
    @"
$markerStart
[features.multi_agent_v2]
plaintext_inter_agent_messages = true
tool_namespace = "external_agents"

[model_providers.deepseek]
name = "DeepSeek"
base_url = "https://api.deepseek.com"
wire_api = "responses"
env_key = "DEEPSEEK_API_KEY"
requires_openai_auth = false

[agents.deepseek_test]
description = "Read-only DeepSeek smoke-test agent"
config_file = "$escapedAgentPath"
$markerEnd
"@
}

function Get-StatusObject {
    $configText = if (Test-Path -LiteralPath $configPath) {
        [IO.File]::ReadAllText($configPath)
    } else { '' }
    $settingsText = if (Test-Path -LiteralPath $vscodeSettingsPath) {
        [IO.File]::ReadAllText($vscodeSettingsPath)
    } else { '' }
    [pscustomobject]@{
        codex_home = $CodexHome
        codex_home_source = $codexHomeSource
        primary_provider_setting_added = $false
        provider_block_enabled = $configText.Contains($markerStart)
        deepseek_env_present = -not [string]::IsNullOrEmpty(
            [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY')
        )
        agent_profile_present = Test-Path -LiteralPath $agentPath
        patched_binary_present = Test-Path -LiteralPath $binaryPath
        vscode_uses_patched_binary = $settingsText -match '"chatgpt\.cliExecutable"\s*:\s*"[^"\r\n]*codex-external-subagents\.exe"'
    }
}

function Enable-Kit {
    if ([string]::IsNullOrWhiteSpace($CodexHome)) {
        throw 'CODEX_HOME is not set. Pass -CodexHome explicitly.'
    }
    foreach ($requiredPath in @($configPath, $agentPath, $binaryPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required path not found: $requiredPath"
        }
    }
    if ([string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY'))) {
        throw 'DEEPSEEK_API_KEY is not present in this process environment.'
    }

    if (Test-Path -LiteralPath $statePath) {
        $previousState = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
        if ($previousState.schema_version -ne 2) {
            throw 'An unsupported restoration manifest already exists; refusing to overwrite it.'
        }
        if (-not [StringComparer]::OrdinalIgnoreCase.Equals($previousState.config_path, $configPath)) {
            $previousConfigEnabled = $false
            if (Test-Path -LiteralPath $previousState.config_path) {
                $previousConfigText = [IO.File]::ReadAllText($previousState.config_path)
                $previousConfigEnabled = $previousConfigText.Contains($markerStart)
            }
            $previousSettingsEnabled = $false
            if (-not [string]::IsNullOrEmpty($previousState.vscode_settings_path) -and
                -not [string]::IsNullOrEmpty($previousState.vscode_settings_inserted_text) -and
                (Test-Path -LiteralPath $previousState.vscode_settings_path)) {
                $previousSettingsText = [IO.File]::ReadAllText($previousState.vscode_settings_path)
                $previousSettingsEnabled = $previousSettingsText.Contains($previousState.vscode_settings_inserted_text)
            }
            if ($previousConfigEnabled -or $previousSettingsEnabled) {
                throw "The kit is still enabled for another CODEX_HOME: $($previousState.config_path). Disable that environment before enabling this one."
            }
        }
    }

    $configBeforeHash = Get-Hash $configPath
    $configInsertionOffset = $null
    $configInsertedText = $null
    $configText = [IO.File]::ReadAllText($configPath)
    if ($configText.Contains($markerStart)) {
        if (-not (Test-Path -LiteralPath $statePath)) {
            throw 'The managed block is enabled but its manifest is missing; refusing to replace recovery state.'
        }
        $existingState = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
        if ($existingState.schema_version -ne 2 -or $existingState.config_path -cne $configPath) {
            throw 'The managed block is enabled but its manifest does not match this CODEX_HOME.'
        }
        return
    }
    if (-not $configText.Contains($markerStart)) {
        if ($configText -match '(?m)^\s*\[model_providers\.deepseek\]\s*$' -or
            $configText -match '(?m)^\s*\[agents\.deepseek_test\]\s*$' -or
            $configText -match '(?m)^\s*\[features\.multi_agent_v2\]\s*$') {
            throw 'Existing DeepSeek provider, deepseek_test agent, or multi_agent_v2 config found outside the managed block; merge the documented fragment manually.'
        }
        $separator = if ($configText.EndsWith("`n")) { "`n" } else { "`r`n`r`n" }
        $configInsertionOffset = $configText.Length
        $configInsertedText = $separator + (Get-ProviderBlock) + "`r`n"
        [IO.File]::AppendAllText($configPath, $configInsertedText)
    }

    $settingsBeforeHash = Get-Hash $vscodeSettingsPath
    $settingsInsertionOffset = $null
    $settingsInsertedText = $null
    if (Test-Path -LiteralPath $vscodeSettingsPath) {
        $settingsText = [IO.File]::ReadAllText($vscodeSettingsPath)
        if ($settingsText -notmatch '"chatgpt\.cliExecutable"\s*:') {
            $closingBrace = $settingsText.LastIndexOf('}')
            if ($closingBrace -lt 0) { throw "VS Code settings are not a JSON object: $vscodeSettingsPath" }
            $beforeBrace = $settingsText.Substring(0, $closingBrace)
            $trimmedBeforeBrace = $beforeBrace.TrimEnd()
            $comma = if ($trimmedBeforeBrace.EndsWith('{')) { '' } elseif ($trimmedBeforeBrace.EndsWith(',')) { '' } else { ',' }
            $jsonBinaryPath = $binaryPath | ConvertTo-Json -Compress
            $settingsInsertionOffset = $trimmedBeforeBrace.Length
            $settingsInsertedText = $comma + "`r`n    `"chatgpt.cliExecutable`": $jsonBinaryPath"
            $updatedSettings = $settingsText.Insert($settingsInsertionOffset, $settingsInsertedText)
            [IO.File]::WriteAllText($vscodeSettingsPath, $updatedSettings, [Text.UTF8Encoding]::new($false))
        } elseif ($settingsText -notmatch [regex]::Escape($binaryPath.Replace('\', '\\'))) {
            throw 'chatgpt.cliExecutable is already set to another binary; refusing to overwrite it.'
        }
    }

    $stateDirectory = Split-Path $statePath -Parent
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    [pscustomobject]@{
        schema_version = 2
        enabled_at = (Get-Date).ToUniversalTime().ToString('o')
        config_path = $configPath
        config_before_sha256 = $configBeforeHash
        config_after_sha256 = Get-Hash $configPath
        config_insertion_offset = $configInsertionOffset
        config_inserted_text = $configInsertedText
        agent_path = $agentPath
        binary_path = $binaryPath
        vscode_settings_path = if (Test-Path -LiteralPath $vscodeSettingsPath) { $vscodeSettingsPath } else { $null }
        vscode_settings_before_sha256 = $settingsBeforeHash
        vscode_settings_after_sha256 = Get-Hash $vscodeSettingsPath
        vscode_settings_insertion_offset = $settingsInsertionOffset
        vscode_settings_inserted_text = $settingsInsertedText
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding utf8
}

function Disable-Kit {
    $status = Get-StatusObject
    if (-not $status.provider_block_enabled -and -not $status.vscode_uses_patched_binary) {
        return
    }
    if (-not (Test-Path -LiteralPath $statePath)) {
        throw "Compatibility-kit manifest not found; refusing an untracked restore: $statePath"
    }
    $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
    if ($state.schema_version -ne 2) {
        throw 'Unsupported compatibility-kit manifest; refusing an untracked restore.'
    }
    if ($state.config_path -cne $configPath) {
        throw 'The manifest belongs to a different CODEX_HOME; pass the original -CodexHome value.'
    }
    if ($status.provider_block_enabled -and
        $null -ne $state.config_insertion_offset -and
        $null -ne $state.config_inserted_text) {
        Remove-ManagedInsertion $configPath $state.config_insertion_offset $state.config_inserted_text 'Codex config'
    }
    if ($status.vscode_uses_patched_binary -and
        $null -ne $state.vscode_settings_path -and
        $null -ne $state.vscode_settings_insertion_offset -and
        $null -ne $state.vscode_settings_inserted_text) {
        Remove-ManagedInsertion $state.vscode_settings_path $state.vscode_settings_insertion_offset $state.vscode_settings_inserted_text 'VS Code settings'
    }
}

switch ($Action) {
    'enable' {
        Enable-Kit
        Get-StatusObject | Format-List
    }
    'disable' {
        Disable-Kit
        Get-StatusObject | Format-List
    }
    'status' {
        Get-StatusObject | Format-List
    }
    'doctor' {
        $status = Get-StatusObject
        $status | Format-List
        if (-not $status.patched_binary_present) { throw "Patched binary not found: $binaryPath" }
        & $binaryPath --version
        if ($status.provider_block_enabled) {
            $doctorJson = & $binaryPath doctor --json 2>$null
            $doctor = $doctorJson | ConvertFrom-Json
            [pscustomobject]@{
                config_parse = $doctor.checks.'config.load'.status
                primary_model = $doctor.checks.'config.load'.details.model
                primary_provider = $doctor.checks.'config.load'.details.'model provider'
            } | Format-List
        }
    }
}

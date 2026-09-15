[CmdletBinding()]
param(
    [string]$SourceDirectory,
    [switch]$SkipTests,
    [switch]$BuildCodeModeHost
)

$ErrorActionPreference = 'Stop'
$kitRoot = $PSScriptRoot
$upstreamTag = 'rust-v0.154.0-alpha.6.2'
$patchPath = Join-Path $kitRoot 'patches\codex-v0.154.0-alpha.6.2-external-subagents.patch'
$binDirectory = Join-Path $kitRoot 'bin'

if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
    $SourceDirectory = Join-Path ([IO.Path]::GetTempPath()) (
        'cmx-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    )
}
$SourceDirectory = [IO.Path]::GetFullPath($SourceDirectory)

if (Test-Path -LiteralPath $SourceDirectory) {
    throw "Build source directory already exists: $SourceDirectory"
}
if (-not (Test-Path -LiteralPath $patchPath -PathType Leaf)) {
    throw "Compatibility patch not found: $patchPath"
}

git clone --depth 1 --branch $upstreamTag https://github.com/openai/codex.git $SourceDirectory
if ($LASTEXITCODE -ne 0) { throw 'Failed to clone the pinned OpenAI Codex source.' }

git -C $SourceDirectory apply --check $patchPath
if ($LASTEXITCODE -ne 0) { throw 'The compatibility patch does not apply cleanly.' }
git -C $SourceDirectory apply $patchPath
if ($LASTEXITCODE -ne 0) { throw 'Failed to apply the compatibility patch.' }

$rustRoot = Join-Path $SourceDirectory 'codex-rs'
Push-Location $rustRoot
try {
    if (-not $SkipTests) {
        cargo test -p codex-core apply_role_can_select_registered_provider_with_read_only_auto_review
        if ($LASTEXITCODE -ne 0) { throw 'External role routing test failed.' }
        cargo test -p codex-core apply_role_cannot_expand_parent_authority
        if ($LASTEXITCODE -ne 0) { throw 'Role authority regression test failed.' }
        cargo test -p codex-core guardian_review_session_config_routes_reserved_reviewer_from_external_provider_to_openai
        if ($LASTEXITCODE -ne 0) { throw 'Automatic reviewer routing test failed.' }
        cargo test -p codex-core guardian_review_session_config_keeps_bedrock_provider_for_bedrock_gpt_5_4
        if ($LASTEXITCODE -ne 0) { throw 'Guardian provider regression test failed.' }
        cargo test -p codex-core custom_multi_agent_namespace_uses_plaintext_message_source
        if ($LASTEXITCODE -ne 0) { throw 'Plaintext transport test failed.' }
        cargo test -p codex-features multi_agent_v2_feature_config_deserializes_table
        if ($LASTEXITCODE -ne 0) { throw 'Feature configuration test failed.' }
    }

    cargo build --release -p codex-cli --bin codex
    if ($LASTEXITCODE -ne 0) { throw 'Codex release build failed.' }
    if ($BuildCodeModeHost) {
        cargo build --release -p codex-code-mode-host
        if ($LASTEXITCODE -ne 0) { throw 'Code-mode host release build failed.' }
    }
} finally {
    Pop-Location
}

New-Item -ItemType Directory -Path $binDirectory -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $rustRoot 'target\release\codex.exe') `
    -Destination (Join-Path $binDirectory 'codex-external-subagents.exe') -Force
if ($BuildCodeModeHost) {
    Copy-Item -LiteralPath (Join-Path $rustRoot 'target\release\codex-code-mode-host.exe') `
        -Destination (Join-Path $binDirectory 'codex-code-mode-host.exe') -Force
}

$builtFiles = @((Join-Path $binDirectory 'codex-external-subagents.exe'))
if ($BuildCodeModeHost) {
    $builtFiles += Join-Path $binDirectory 'codex-code-mode-host.exe'
}
Get-FileHash -Algorithm SHA256 -LiteralPath $builtFiles

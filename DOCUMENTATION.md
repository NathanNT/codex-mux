# Codex external-provider subagents documentation

## Overview

This kit keeps the primary Codex agent on its existing OpenAI configuration while allowing explicitly selected native Codex subagents to use a separately registered, Responses-compatible provider. DeepSeek is the included example, but the design follows Codex's provider abstraction.

The kit targets the VS Code extension's bundled Codex version `0.154.0-alpha.6.2`. It uses a side-by-side executable and never replaces the original Codex installation. The included `deepseek_test` agent uses a read-only sandbox and OpenAI automatic approval review.

## Why a compatibility build is required

Native configuration was tested first. The installed Codex implementation created a native child but discarded the custom role's `model_provider`, causing it to contact OpenAI with the DeepSeek model name.

After provider propagation was corrected, DeepSeek received requests but not the delegated task. The native OpenAI collaboration schema transported the task as an encrypted proprietary item that DeepSeek could neither decrypt nor consume as a standard user message.

The compatibility build makes the smallest required changes:

- preserve a role's registered `model_provider` when spawning a child;
- provide an opt-in plaintext inter-agent message mode under a non-reserved tool namespace;
- convert plaintext agent messages to standard user messages only for non-OpenAI providers;
- fail clearly instead of silently falling back to OpenAI;
- route the reserved automatic approval reviewer through OpenAI when an external worker triggers it;
- preserve native Codex threads, tools, parallelism, follow-up transport, and result collection;
- allow an agent profile to reduce its sandbox to read-only without expanding parent authority.

OpenAI wire behavior remains unchanged when the compatibility feature is disabled.

## Approval-routing decision and maintenance cost

The first implementation solved IDA MCP approval failures inside Codex itself.
When an external-provider child triggered automatic review, the reserved
`codex-auto-review` model inherited the child's DeepSeek provider. DeepSeek
rightly rejected that OpenAI-only model name. The compatibility patch now
creates that reserved review session with the registered OpenAI provider.

That fix is general and the validated binary works, but it is expensive to
maintain for the narrower IDA use case. A cold Windows release build compiles
the complete Rust CLI with release optimizations and can take tens of minutes.
The initial diagnosis also required two builds because `approval_policy =
"never"` by itself rejects an MCP operation that still requires approval.

For a known read-only MCP surface, prefer Codex's native per-tool approval
configuration before adding or porting a core patch. The pinned Codex source
maps `approval_mode = "approve"` to execution without an approval request, and
the official configuration reference exposes the setting at
`mcp_servers.<id>.tools.<tool>.approval_mode`.

Keep the current OpenAI reviewer-routing patch as a tested fallback for tools
that genuinely need automatic review. For the next Codex port, first evaluate
whether an explicit read-only IDA allowlist removes the need to carry that
specific part of the source patch.

## Minimal read-only IDA procedure

This is the preferred low-maintenance design for DeepSeek workers that only
inspect IDA databases. It has not replaced the current release profile yet;
apply and smoke-test it deliberately during the next maintenance window.

1. Inventory the exact IDA MCP tools required by the workers and classify each
   one from its implementation, not its name alone.
2. Keep the IDA server default approval mode restrictive.
3. Set `approval_mode = "approve"` only for individually audited read-only
   tools.
4. Use a read-only worker sandbox with `approval_policy = "never"` and omit the
   automatic reviewer from that profile.
5. Restart Codex, invoke every allowlisted tool once, and confirm from runtime
   metadata that no `codex-auto-review` request was created.
6. Leave new, unknown, mutating, database-writing, debugger, scripting, and
   process-control tools unapproved. Add a tool only after reviewing it.

Example for the harmless session inventory operation:

```toml
[mcp_servers.ida]
default_tools_approval_mode = "prompt"

[mcp_servers.ida.tools.idb_list]
approval_mode = "approve"
```

Corresponding worker profile:

```toml
model_provider = "deepseek"
model = "deepseek-flash"
sandbox_mode = "read-only"
approval_policy = "never"
```

Do not set `default_tools_approval_mode = "approve"` on the complete IDA MCP
server unless a separate facade exposes only audited read-only operations.
Per-tool entries make tool-set changes fail closed: a newly added IDA method
does not become implicitly trusted.

The durable implementation should make `manage.ps1 doctor` compare the
configured allowlist with a repository-owned list and warn when the IDA MCP
tool inventory changes. Until that check exists, treat the example above as a
manual procedure rather than a claim that all IDA tools are approved safely.

## Repository layout

```text
.
├── agents/
│   ├── deepseek_test.toml
│   └── external_agent.example.toml
├── bin/
│   ├── codex-external-subagents.exe
│   └── codex-code-mode-host.exe
├── providers/
│   ├── deepseek.toml
│   └── responses-provider.example.toml
├── manage.ps1
├── README.md
├── DOCUMENTATION.md
├── LICENSE
├── NOTICE
└── .gitignore
```

`state/manifest.json` is generated by `enable` and ignored by Git. It contains paths, hashes, insertion offsets, and exact managed text, but no credentials.

The executables are also ignored because the patched Codex executable is larger than GitHub's normal per-file limit. They are distributed in a GitHub Release archive that also includes `LICENSE` and `NOTICE`.

The complete source delta is tracked in `patches/`. To reproduce the Windows
executables from the pinned upstream tag, run:

```powershell
.\build.ps1
```

The script clones OpenAI Codex `rust-v0.154.0-alpha.6.2` into a short, unique
temporary directory, verifies and applies the tracked patch, runs focused
tests, builds the patched Codex executable, and copies it into `bin/`. It
refuses to reuse or delete an existing source directory.

The compatibility patch does not modify `codex-code-mode-host`. Keep the
matching host distributed in the release archive. To rebuild that unchanged
component too, use `./build.ps1 -BuildCodeModeHost`; this additionally depends
on the upstream `rusty_v8` binary archive being available.

## Prerequisites

- Windows PowerShell.
- Codex `0.154.0-alpha.6.2`.
- The matching GitHub Release archive extracted into this repository.
- The same `CODEX_HOME` used by the Codex CLI and VS Code extension.
- A local `.env` containing `DEEPSEEK_API_KEY=<value>`.

Run `doctor` after any Codex or extension update. A different Codex version may require a newly matched compatibility build.

## What happens when Codex or the VS Code extension updates

The kit uses a side-by-side executable under this repository and selects it
through the VS Code user setting `chatgpt.cliExecutable`. A normal extension
update should preserve that user setting and does not overwrite the
repository-owned executable.

Consequently, an update normally has these effects:

- the extension itself is updated;
- the newly bundled upstream Codex executable is installed;
- this kit continues to launch its older pinned compatibility executable;
- the source changes are not erased, but new upstream CLI fixes are not active
  in the pinned executable;
- a sufficiently large protocol change may make the updated extension and the
  older compatibility executable incompatible.

Run `manage.ps1 doctor` after every update. To use the newly bundled upstream
Codex immediately, run `manage.ps1 disable` and restart VS Code. This preserves
the repository, patch, and compatibility executable while removing only the
managed selection and configuration. Re-enable only after confirming version
compatibility or producing a matching build.

## Porting and rebuilding for a new Codex version

Use this procedure only when the new upstream behavior is needed and the
existing compatibility executable is no longer the desired target.

1. Close active Codex sessions and record the current working version:

   ```powershell
   .\manage.ps1 status
   .\bin\codex-external-subagents.exe --version
   git status --short
   ```

2. Disable the kit temporarily and restart VS Code so the updated bundled
   executable can be identified and tested independently:

   ```powershell
   .\manage.ps1 disable
   ```

3. Identify the exact matching upstream OpenAI Codex tag. Do not approximate a
   release tag from the extension version.

4. Create a versioned patch filename under `patches/`. Port only the deltas
   still required:

   - external child `model_provider` propagation;
   - opt-in plaintext inter-agent transport for non-OpenAI providers;
   - failure instead of silent provider fallback;
   - read-only child-authority preservation;
   - OpenAI reviewer routing only if the per-tool MCP allowlist cannot cover
     the intended workflow.

5. Update `$upstreamTag` and `$patchPath` in `build.ps1` to the exact new tag
   and patch. Verify the patch before compiling:

   ```powershell
   git clone --depth 1 --branch <exact-upstream-tag> https://github.com/openai/codex.git <new-empty-directory>
   git -C <new-empty-directory> apply --check <absolute-patch-path>
   ```

6. Run the focused tests before the full release build. `build.ps1` performs
   both by default:

   ```powershell
   .\build.ps1
   ```

   A cold release build may take tens of minutes. Do not repeat it merely to
   diagnose a configuration problem. Use targeted `cargo test` commands and a
   debug build in the temporary source checkout until the source delta is
   stable, then perform one final release build.

7. Verify the resulting executable and configuration without exposing the API
   key:

   ```powershell
   .\bin\codex-external-subagents.exe --version
   .\manage.ps1 doctor
   ```

8. Re-enable the kit, restart VS Code, and run these bounded smoke tests:

   - one DeepSeek child reading a harmless repository file;
   - two concurrent read-only children;
   - `idb_list` through the audited IDA configuration;
   - one ordinary OpenAI child;
   - confirmation from runtime metadata that each child used the intended
     provider.

9. Review `git diff`, run a secret scan, commit the source patch and
   documentation, and publish binaries only through a release archive with
   updated checksums, `LICENSE`, and `NOTICE`.

The side-by-side path remains stable, so `chatgpt.cliExecutable` does not need
to change when the rebuilt executable replaces the previous compatibility
binary. Keep the last known-good release archive until the new smoke tests
pass.

## Installation

### 1. Obtain the release archive

Download the Windows archive and `SHA256SUMS.txt` from the [latest GitHub Release](https://github.com/NathanNT/codex-mux/releases/latest). Verify the archive checksum, then extract it into the repository root.

The archive contains:

```text
bin/codex-external-subagents.exe
bin/codex-code-mode-host.exe
LICENSE
NOTICE
```

The validated compatibility executable inside the archive has this SHA-256 hash:

```text
84BD0BC0D6695A3231862DEA512E08FC295CEAE8C95EAF9D159760C4C5291620
```

### 2. Select the active Codex home

The script resolves the environment in this order:

1. an explicit `-CodexHome` argument;
2. the current process's `CODEX_HOME` environment variable;
3. the standard `%USERPROFILE%\.codex` directory.

For one of several Codex environments, pass the correct directory to every command:

```powershell
.\manage.ps1 status -CodexHome 'C:\path\to\codex-home'
```

Do not point the script at a guessed or temporary directory. `enable` updates the `config.toml` inside the selected Codex home.

The status output includes `codex_home_source`, making the selection explicit. A single repository copy manages one enabled environment at a time because restoration is tied to an exact manifest. Disable the current environment before enabling another one; the script refuses to overwrite an active manifest belonging to a different Codex home.

### 3. Load the key from `.env`

The script stores only the credential environment-variable name. If the key exists only in `.env`, load it into the current PowerShell process without displaying it:

```powershell
$envEntry = Get-Content -LiteralPath '.env' |
    Where-Object { $_ -match '^\s*DEEPSEEK_API_KEY\s*=' } |
    Select-Object -First 1

if (-not $envEntry) {
    throw 'DEEPSEEK_API_KEY is missing from .env'
}

$envValue = ($envEntry -split '=', 2)[1].Trim()
if (($envValue.StartsWith('"') -and $envValue.EndsWith('"')) -or
    ($envValue.StartsWith("'") -and $envValue.EndsWith("'"))) {
    $envValue = $envValue.Substring(1, $envValue.Length - 2)
}

$env:DEEPSEEK_API_KEY = $envValue
Remove-Variable envEntry, envValue
```

This modifies only the current process and its child processes. It produces no key output and does not modify `.env`.

### 4. Run the preflight check

```powershell
.\manage.ps1 doctor
```

`doctor` verifies the side-by-side executable and its version. When enabled, it also parses the effective configuration and reports the primary model and provider.

### 5. Enable and verify

```powershell
.\manage.ps1 enable
.\manage.ps1 status
.\manage.ps1 doctor
```

Verify that:

- `provider_block_enabled` is `True`;
- `patched_binary_present` is `True`;
- `vscode_uses_patched_binary` is `True` when VS Code settings are managed;
- `agent_read_only_auto_review` is `True`;
- `primary_provider` remains `openai`.

`enable` refuses to overwrite an existing `deepseek` provider, `deepseek_test` agent, or different `chatgpt.cliExecutable` setting. Repeated enablement is idempotent and preserves the recovery manifest.

Restart VS Code after enabling. When the key is not already in VS Code's environment, start it from the PowerShell process that loaded `.env`:

```powershell
code .
```

Do not persist the key in VS Code settings.

## Usage

The registered native agent type is `deepseek_test`. Only an explicit spawn of this role selects DeepSeek. The parent retains its current OpenAI provider and model.

### Change the external child model

Edit `agents/deepseek_test.toml` and set `model` to an exact model ID supported by the registered provider:

```toml
model_provider = "deepseek"
model = "deepseek-flash"
sandbox_mode = "read-only"
approval_policy = "on-request"
approvals_reviewer = "auto_review"
```

This setting applies only to `deepseek_test`; it does not change the root OpenAI model or provider. Restart Codex or VS Code before spawning a new child so the profile is reloaded.

### Single-child smoke test

Ask the primary agent:

```text
Spawn one native subagent with agent_type deepseek_test. Ask it to read
README.md and return:
1. the filename
2. the first heading
3. the fixed marker DEEPSEEK_CHILD_OK

Wait for the child and report its result. Do not read the file on the
parent's behalf.
```

The child runs in a native Codex thread and can use normal Codex read tools. Its profile enforces `sandbox_mode = "read-only"` and forbids file modification.

### Read-only policy with automatic review

External workers combine these two settings:

```toml
sandbox_mode = "read-only"
approval_policy = "on-request"
approvals_reviewer = "auto_review"
```

Reads, searches, and inspections already permitted by the sandbox proceed
directly. Approval-gated MCP operations and sandbox requests are routed to the
automatic reviewer instead of blocking for user input. The compatibility build
keeps the worker on its selected provider but creates the reserved
`codex-auto-review` session with the registered OpenAI provider. This prevents
the reserved model name from being sent to DeepSeek and preserves the safety
decision.

Do not solve the incompatibility by aliasing `codex-auto-review` to an external
general-purpose model or by weakening the sandbox. Keep privileged, mutating,
or otherwise approval-requiring work with the OpenAI parent.

### Parallel-child test

```text
Spawn two native subagents concurrently with agent_type deepseek_test.
Child A must read README.md and child B must read DOCUMENTATION.md.
Each must return the filename, first heading, and DEEPSEEK_CHILD_OK.
Continue useful parent-side work while both run, then wait for and
summarize both results.
```

Use Codex runtime metadata or local rollout metadata to verify the selected provider. Model self-identification is not proof of provider selection.

## Managed configuration

`enable` appends one clearly marked block to the active Codex configuration. The real `config_file` path is resolved to this repository's local agent file.

```toml
# BEGIN codex-external-subagents-kit
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
config_file = "C:\\path\\to\\repository\\agents\\deepseek_test.toml"
# END codex-external-subagents-kit
```

The script never sets the root `model`, root `model_provider`, OpenAI login, approval policy, or root sandbox policy.

## Management commands

### Status

```powershell
.\manage.ps1 status
```

Reports the selected Codex home, managed provider state, key presence, agent profile, executable, and VS Code executable selection. It never prints the key.

Use `-CodexHome '<absolute-path>'` to target a specific Codex environment directly.

### Doctor

```powershell
.\manage.ps1 doctor
```

Checks the executable version, verifies that the DeepSeek profile is read-only
with automatic review, and, when enabled, validates configuration
parsing plus the primary model/provider.

### Enable

```powershell
.\manage.ps1 enable
```

Adds only the managed configuration and VS Code executable setting, then writes the restoration manifest.

### Disable

```powershell
.\manage.ps1 disable
```

Removes only the exact manifest-recorded insertions.

## Restoration

Use the same `CODEX_HOME` or the same explicit `-CodexHome` path used during installation.

```powershell
.\manage.ps1 status
.\manage.ps1 disable
.\manage.ps1 status
```

Confirm that `provider_block_enabled` and `vscode_uses_patched_binary` are `False`, then restart VS Code. The normal bundled executable will be used again.

Restoration removes `chatgpt.cliExecutable` only when the kit inserted it. Unrelated user settings, the primary OpenAI configuration, and the original installation remain unchanged.

### Restoration conflict handling

`disable` stops if later edits overlap managed text or if the manifest belongs to another Codex home. It does not guess or overwrite newer content.

If restoration refuses to proceed:

1. Confirm the exact `-CodexHome` used during `enable`.
2. Inspect the marked block in that home's `config.toml` and the paths in `state/manifest.json`.
3. Move overlapping manual changes outside the managed block.
4. Run `disable` again.

Do not delete the manifest before successful restoration and do not remove configuration with a broad search-and-replace.

## Add another provider or agent

1. Copy `providers/responses-provider.example.toml` and choose a unique provider ID.
2. Configure its `base_url`, `wire_api = "responses"`, and `env_key`.
3. Store only the environment-variable name, never the credential value.
4. Copy `agents/external_agent.example.toml` and set `model_provider` to the registered ID.
5. Select a model supported by that endpoint.
6. Preserve `sandbox_mode = "read-only"`, `approval_policy = "on-request"`, and `approvals_reviewer = "auto_review"` for an automatically reviewed read-only worker.
7. Register the profile under `[agents.<name>]` in the trusted parent configuration.

Provider URLs and authentication definitions remain parent-owned. Agent profiles select registered provider IDs but cannot redefine provider authentication.

To remove one agent, remove its `[agents.<name>]` declaration and profile file. To disable the complete managed setup, use `manage.ps1 disable`.

## Security properties

- No API key is stored in repository files or Codex configuration.
- `.env`, generated state, and release executables are ignored by Git.
- Authorization headers are not logged by this kit.
- External-provider failures are surfaced and never silently rerouted to OpenAI.
- The test agent is read-only; approval-gated actions are decided by OpenAI's automatic reviewer rather than the external worker.
- Mandatory automatic approval reviews use OpenAI's reserved reviewer rather than the external worker provider.
- Agent profiles cannot expand sandbox permissions, approval policy, or writable roots.
- The primary OpenAI provider is unchanged.

Plaintext compatibility mode means delegated task text and follow-up messages may appear in local Codex rollout logs. Never include credentials or other sensitive values in subagent task messages.

## License and attribution

This repository and its distributed compatibility build are provided under the Apache License 2.0. A complete copy is included in `LICENSE`.

The executable is a modified object-code build derived from OpenAI Codex `0.154.0-alpha.6.2`. `NOTICE` preserves the upstream OpenAI Codex and Ratatui attribution notices and prominently identifies this distribution as modified. The source areas changed by this compatibility build are listed in the validation section below.

OpenAI trademarks are used only to describe the origin and compatibility target. This project is independent and is not affiliated with or endorsed by OpenAI.

Every binary release archive includes `LICENSE` and `NOTICE` alongside the executables. Users redistributing the archive or binaries should preserve those files and review the license obligations applicable to their distribution.

## Validation evidence

The completed runtime test used:

- OpenAI parent: `gpt-5.6-sol` through `openai`;
- two concurrent native DeepSeek children: `deepseek-flash` through `deepseek`;
- one concurrent normal OpenAI child;
- normal native child tools and native result collection;
- a workspace-write parent with a read-only DeepSeek child.

Runtime metadata linked every child to the parent through native `subagent.thread_spawn` metadata. Both DeepSeek children overlapped in execution, and the parent performed useful file-reading work while all three children were active. Provider identity came from runtime metadata, not model self-reporting.

Regression coverage included provider propagation, plaintext message conversion, encrypted-message rejection for external providers, configurable tool namespaces, feature-table parsing, read-only sandbox preservation, cold resume, native follow-up transport, configuration restoration, and enablement idempotency.

The relevant modified Codex source areas were:

- `core/src/agent/control/spawn.rs`;
- `core/src/agent/role.rs` and its tests;
- `core/src/client.rs` and its tests;
- `core/src/config/mod.rs` and configuration tests;
- `core/src/guardian/reviewer_config.rs` and Guardian tests;
- native multi-agent handlers, tool specifications, router, and their tests;
- multi-agent resume integration tests;
- `features/src/feature_configs.rs`.

## Official references

- [Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)
- [Codex subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [OpenAI Codex source repository](https://github.com/openai/codex)

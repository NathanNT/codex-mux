# Codex external-provider subagents

A reversible compatibility kit for running native Codex subagents through an external Responses-compatible provider while the primary agent remains on OpenAI.

The included profile uses DeepSeek and is read-only. This build targets Codex `0.154.0-alpha.6.2`.

The external child uses a read-only sandbox with automatic approval review.
Ordinary reads proceed directly; approval-gated MCP operations are reviewed by
OpenAI without a manual prompt. When review uses the reserved
`codex-auto-review` model, the compatibility build routes that reviewer through
the registered OpenAI provider while normal worker inference continues through
DeepSeek.

## Select the Codex environment

The script resolves the target environment in this order:

1. `-CodexHome 'C:\path\to\codex-home'`
2. the current process's `CODEX_HOME` environment variable
3. the standard default `%USERPROFILE%\.codex`

For a specific environment, pass the same path to every command:

```powershell
$selectedCodexHome = 'C:\path\to\my-codex-environment\codex'
.\manage.ps1 doctor -CodexHome $selectedCodexHome
.\manage.ps1 enable -CodexHome $selectedCodexHome
.\manage.ps1 status -CodexHome $selectedCodexHome
```

The status output shows both `codex_home` and `codex_home_source`. One repository copy manages one enabled Codex environment at a time. Run `disable` with the same `-CodexHome` before enabling another one.

## Change the external model

Edit `agents/deepseek_test.toml` and replace the model ID with one supported by the registered provider:

```toml
model_provider = "deepseek"
model = "deepseek-flash"
```

This changes only the `deepseek_test` child. It does not change the primary OpenAI model or provider. Restart Codex or VS Code before spawning a new child.

The profile deliberately combines:

```toml
sandbox_mode = "read-only"
approval_policy = "on-request"
approvals_reviewer = "auto_review"
```

This is permissive for reads already in scope and routes approval-gated MCP or
sandbox requests to OpenAI's automatic reviewer. It does not disable mandatory
ARC or Guardian review.

## Download

Download the Windows archive and `SHA256SUMS.txt` from the [latest GitHub Release](https://github.com/NathanNT/codex-mux/releases/latest). Verify the archive checksum, then extract it into the repository root. The archive includes both required executables together with `LICENSE` and `NOTICE`.

## Quick start

From PowerShell, with the existing `DEEPSEEK_API_KEY` loaded into the process environment:

```powershell
.\manage.ps1 doctor
.\manage.ps1 enable
.\manage.ps1 status
```

Restart VS Code from the same environment, then ask Codex to spawn a native subagent with `agent_type = "deepseek_test"`.

Restore the original configuration at any time:

```powershell
.\manage.ps1 disable
```

The original Codex installation and primary OpenAI configuration are never replaced.

See [DOCUMENTATION.md](DOCUMENTATION.md) for installation, usage, verification, security, provider configuration, and restoration details.

The compatibility source delta is included under `patches/`; `build.ps1`
reproduces the patched Codex executable from the pinned upstream tag. The
unchanged matching code-mode host remains part of the release archive.

## License

This project is distributed under the [Apache License 2.0](LICENSE). The executable is a modified build derived from [OpenAI Codex](https://github.com/openai/codex); attribution and modification details are in [NOTICE](NOTICE). This independent project is not affiliated with or endorsed by OpenAI.

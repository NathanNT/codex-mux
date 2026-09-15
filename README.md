# Codex external-provider subagents

A reversible compatibility kit for running native Codex subagents through an external Responses-compatible provider while the primary agent remains on OpenAI.

The included profile uses DeepSeek and is read-only. This build targets Codex `0.154.0-alpha.6.2`.

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

## License

This project is distributed under the [Apache License 2.0](LICENSE). The executable is a modified build derived from [OpenAI Codex](https://github.com/openai/codex); attribution and modification details are in [NOTICE](NOTICE). This independent project is not affiliated with or endorsed by OpenAI.

# Maintenance instructions for Codex agents

## Purpose and current baseline

This repository provides a reversible, side-by-side Codex compatibility build
that lets selected native subagents use a registered external
Responses-compatible provider while the parent remains on OpenAI.

The current baseline targets OpenAI Codex `rust-v0.154.0-alpha.6.2`. The
tracked patch includes external-provider propagation, opt-in plaintext
inter-agent transport, read-only child-authority preservation, and a fallback
that routes the reserved `codex-auto-review` session through OpenAI.

## Read before changing anything

Read these files completely in this order:

1. `README.md`
2. `DOCUMENTATION.md`
3. `agents/deepseek_test.toml`
4. `manage.ps1`
5. `build.ps1`
6. the versioned patch under `patches/`

Inspect `git status` before editing and preserve unrelated changes.

## Preferred maintenance strategy

Use configuration before patching Codex core. For audited read-only IDA MCP
operations, prefer explicit
`mcp_servers.<id>.tools.<tool>.approval_mode = "approve"` entries, a read-only
sandbox, and `approval_policy = "never"`. Keep the server default restrictive
and approve tools individually.

Do not approve the complete IDA MCP surface merely because the worker sandbox
is read-only: an MCP tool executes outside the filesystem sandbox and may
modify an IDB, control a debugger, run scripts, or affect another process.

The OpenAI reviewer-routing source change is a tested fallback, not the first
choice for a known read-only tool set. Carry it into a future Codex version
only when automatic review is actually required after the per-tool design has
been tested.

## Updating the pinned Codex version

Follow `DOCUMENTATION.md` sections “What happens when Codex or the VS Code
extension updates” and “Porting and rebuilding for a new Codex version.”

For every port:

- identify the exact upstream tag used by the updated bundled executable;
- create a new versioned patch instead of overwriting historical evidence;
- update both `$upstreamTag` and `$patchPath` in `build.ps1`;
- apply the patch to a fresh checkout and run focused tests before a release
  build;
- retain only compatibility deltas still required by the new upstream code;
- run provider, plaintext transport, authority, resume, follow-up, concurrent
  child, and IDA read-only smoke tests;
- confirm provider selection through runtime metadata, not model
  self-identification.

A cold optimized Rust build is expensive. Diagnose patch and configuration
failures with focused tests before performing one final release build.

## Repository and secret hygiene

- Never commit `.env`, API keys, authorization headers, rollout data, generated
  state, private Codex configuration, or local machine paths containing
  credentials.
- Keep executables out of Git; distribute them through a release archive with
  checksums, `LICENSE`, and `NOTICE`.
- Do not replace the user's bundled Codex executable. Continue using the
  side-by-side binary and reversible `chatgpt.cliExecutable` selection.
- Make restoration changes only through the exact manifest-tracked insertions
  in `manage.ps1`.
- Preserve fail-closed behavior for unknown providers, encrypted external
  messages, unapproved MCP tools, and authority expansion attempts.

## Required checks before commit or push

At minimum:

```powershell
git status --short
git diff --check
.\manage.ps1 status
.\manage.ps1 doctor
```

Also inspect the staged diff, scan tracked files for credentials and private
tokens, and verify that no executable, `.env`, generated state, or temporary
checkout is staged. A documentation-only change does not justify rebuilding
the Codex binary.

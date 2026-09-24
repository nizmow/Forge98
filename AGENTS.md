# Agent Instructions

## Shell and Tooling

Use the shell appropriate for the host operating system rather than assuming
that every checkout runs on Windows:

- On Windows, use PowerShell 7 (`pwsh`) for project commands and `.ps1` scripts.
  If the editor terminal starts through a POSIX-compatible wrapper, invoke it
  explicitly:

  ```text
  pwsh -NoProfile -Command "<command>"
  pwsh -NoProfile -File <script.ps1>
  ```

- On macOS or Linux, use the native POSIX shell for ad-hoc commands and
  platform-specific workflows. Repository automation should still use
  cross-platform PowerShell 7 (`pwsh`) rather than adding a parallel Bash
  implementation.

Use PowerShell scripts for new repository automation on every host. Keep them
portable to PowerShell 7, not Windows PowerShell-only, and run them through the
mise environment when possible:

```text
mise exec -- pwsh -NoProfile -File <script.ps1>
```

Use the repository's `mise.toml` as the source of truth for project tooling.

- Run project tasks with `mise run <task>` from the repository root.
- Run project commands that need the configured environment with `mise exec -- <command>`.
- Prefer tools exposed by the mise environment over globally installed versions.
- Check `mise.toml` before adding a new command, dependency, or tool-specific setup.
- Keep generated build, VM, and download artifacts in the existing ignored directories.

## Project Script Entry Points

- Expose every host-side script intended for direct developer use as a task in
  `mise.toml`; document and invoke those workflows with `mise run <task>`.
- Keep helper scripts and modules that are only called by a task's entry-point
  script internal; they do not need a separate task.
- Treat mise tasks as the stable project interface. Tasks may invoke PowerShell
  scripts today and should invoke the selected build system when one is adopted.
- When a workflow needs inputs, expose them as task arguments or options and
  forward them to the underlying script/build command.

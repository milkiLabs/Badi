# Documentation

This directory is the developer's reference. The user-facing
configuration docs are in [`user-docs/`](user-docs/).

## For new contributors

Start here, in this order:

1. **[codebase-structure.md](codebase-structure.md)** — module layering
   and the rules that keep `core/` and `ui/` separate. Read first.
2. **[architecture.md](architecture.md)** — startup flow, mode
   detection, how the first frame is prepared.
3. **[app-lifecycle.md](app-lifecycle.md)** — the `App.create` →
   `App.run` → `App.destroy` sequence, error handling, who owns what.
4. **[modes.md](modes.md)** — per-mode behavior reference and how
   mode transitions work. How to add a new mode.
5. **[performance.md](performance.md)** — the model-view rendering
   approach, streaming append, and fixed row heights.

## Per-feature deep dives

- **[piped-mode.md](piped-mode.md)** — async stdin pipeline,
  buffering, EOF handling.
- **[prompt-mode.md](prompt-mode.md)** — `--prompt` mode flags,
  behavior, and exit codes.
- **[stdin-detection.md](stdin-detection.md)** — TTY vs pipe vs
  `/dev/null` detection via `stat().kind`.
- **[launch-history.md](launch-history.md)** — per-app launch counts,
  `log2(count)` ranking boost, and the `history.json` storage format.
- **[cicd.md](cicd.md)** — release build workflow on tag push
  (tarball + AppImage).
- **[appimage.md](appimage.md)** — building and troubleshooting the
  AppImage locally.

## User-facing configuration

- **[user-docs/actions.md](user-docs/actions.md)** — `config.json`
  prefix actions.
- **[user-docs/theme.md](user-docs/theme.md)** — `theme.json` visual
  customization.
- **[user-docs/shortcuts.md](user-docs/shortcuts.md)** — keyboard
  shortcuts reference.
- **[user-docs/search-algo.md](user-docs/search-algo.md)** — how the
  search ranking works (substring, multi-token, acronym).

## How the docs are organized

The audience for each doc:

| Audience             | Doc                                                |
| -------------------- | -------------------------------------------------- |
| New contributors     | codebase-structure → architecture → app-lifecycle  |
| Adding a new mode    | modes.md                                          |
| Adding a new signal  | ui/callbacks/* (in code), modes.md, architecture.md |
| Debugging rendering  | performance.md                                    |
| Configuring Badi     | user-docs/* (linked from README.md)                |
| Releasing            | cicd.md, appimage.md                              |

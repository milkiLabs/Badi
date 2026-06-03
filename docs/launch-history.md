# App Launch History

Badi remembers which apps you launch and uses the count to nudge the
result list toward your frequent picks. The signal is intentionally
weak: it breaks relevance ties and reorders empty queries, but it
cannot overpower a clearly better textual match.

## What gets recorded

A successful app launch (one that exits with code `0` from `modes/apps`)
increments the count for that app's stable `.desktop` id. The id is
the basename of the `.desktop` file (e.g. `firefox.desktop`), kept
on `DesktopEntry.id` and exposed via `core.desktop.idOf`. A missing
or empty id falls back to the display name, so the bookkeeping still
works for entries that haven't been rewritten with an id.

Launches that fail (`exit_code != 0`) are **not** recorded. Cancel
via Escape also doesn't record — only the Enter/double-click path
through `modes/apps.launch` does.

## Storage

File: `$XDG_DATA_HOME/badi/history.json`
(falls back to `$HOME/.local/share/badi/history.json`).

Shape:

```json
{
  "launch_counts": {
    "firefox.desktop": 47,
    "kitty.desktop": 12,
    "code.desktop": 3
  }
}
```

- Plain JSON, one integer per app id.
- Unknown fields are ignored on load.
- Non-integer or out-of-range values are skipped (no error).
- The file is rewritten in full on every save; a 1 MB cap on the
  read side (`max_history_file_size`) protects against runaway files.
- Save failures are logged via `std.log.warn` and otherwise ignored —
  the in-memory counts survive until exit, so a read-only home
  directory doesn't lose data on the next launch.

The directory is created on first write via
`std.Io.Dir.cwd().createDirPathOpen`, so the user never has to mkdir
it.

## Ranking signal

`launch_history.launchBoost(count)` is the additive signal fed to
`core.search.searchMappedBoosted`:

```
count: 0  1  2  3  4  5  6  7   8  16  32  64  128
boost: 0  0  1  1  2  2  2  2   3   4   5   6    7
```

`log2` growth means a wildly-launched app (Firefox at 100 launches)
gets a +6 nudge, while a casual app (5 launches) gets +2. The base
substring match scores are in the thousands (see
[user-docs/search-algo.md](user-docs/search-algo.md)), so the boost
only matters when text relevance is close.

### Empty query

When the input is empty, the apps list reorders by history boost
alone (`ui/view.rankAppsByHistory`). Apps you've never launched sit
at the bottom in source order (which is `.desktop` file name order
— deterministic, but not personalized). Once you start typing,
textual relevance takes over and history is a tie-breaker.

## Flow at a glance

```
startup.buildState
  └── core.launch_history.load(env, io)
        └── read $XDG_DATA_HOME/badi/history.json
            (creates dir on demand, ignores all errors)

ui/view.fillApps(empty query)
  └── rankAppsByHistory → sort by boost desc

ui/view.fillApps(non-empty query)
  └── searchMappedBoosted(... appHistoryBoost ...)
        └── sort by (text score + boost) desc

modes/apps.launch (on Enter)
  └── util.launchDetached(...)
  └── if exit_code == 0: app.launched_app_id = selection.app_id

app/exit_code.resolve (after event loop)
  └── if code == 0: recordSuccessfulAppLaunch
        └── core.launch_history.recordLaunch
              └── History.increment  (in-memory)
              └── save              (rewrite history.json)
```

The recording happens in `exit_code.resolve` rather than in
`modes/apps.launch` so that the increment is observed exactly once
per Badi invocation, regardless of how the user closes the window
(Enter, double-click, or programmatic close after a successful
launch).

## Why the signal is so small

- The substring/acronym match scores are in the thousands. A large
  history boost would let "firefox" with 500 launches outrank
  "firefox-nightly" typed in plain text.
- The "Apps" mode list is small (typically 50–200 entries). A weak
  signal is enough to re-rank; a strong one would be surprising.
- Personal ranking is best-effort. A fresh install with no history
  must behave exactly like the old code.

## Adding the same signal to another mode

`searchMappedBoosted` is generic over `(T, getText, getBoost, ctx)`.
`getBoost` receives a `*const anyopaque` so the history map can
hide behind the comptime interface. See
`core.search.searchMappedBoosted` and its test in
`src/core/search.zig` for the contract.

## Source Files

| File                            | Purpose                                                       |
| ------------------------------- | ------------------------------------------------------------- |
| `src/core/launch_history.zig`   | `History` struct, `load`, `save`, `recordLaunch`, `launchBoost` |
| `src/core/desktop/entry.zig`    | `DesktopEntry.id` + `idOf` (stable app key)                  |
| `src/core/desktop/loader.zig`   | Duplicates `.desktop` basename into `id` field                |
| `src/core/desktop/mod.zig`      | Re-exports `idOf`                                             |
| `src/core/search.zig`           | `searchMappedBoosted`, `sortScored` (generic ranking)         |
| `src/app/startup.zig`           | `launch_history.load(...)` wired into `AppState`              |
| `src/app/exit_code.zig`         | `recordSuccessfulAppLaunch` (single write site)               |
| `src/modes/apps.zig`            | Sets `app.launched_app_id` after a successful launch          |
| `src/state/app_state.zig`       | `launch_history`, `launched_app_id` fields                    |
| `src/ui/view.zig`               | `fillApps`, `rankAppsByHistory`, `appHistoryBoost`           |

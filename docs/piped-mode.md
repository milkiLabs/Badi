# Piped Mode

Data is streamed from stdin via `QSocketNotifier` — the window appears
immediately and items arrive asynchronously. The user can filter before all
lines have arrived.

## How it works

1. Window shows "Waiting for input..."
2. `QSocketNotifier` watches `STDIN_FILENO` via Qt's event loop
3. When data arrives, `onStdinActivated` (in `src/ui/callbacks/piped.zig`)
   reads up to 64 KB via `std.posix.read`
4. Raw bytes accumulate in `AppState.stdin_pending`, split on `\n`
5. Complete lines are trimmed (CR stripped) and added to the list
   immediately via `piped_view.appendPipedItem`
6. On EOF: flush remaining bytes via `flushTrailingLine`, disable the
   notifier, set `app.stdin_eof = true`

## Buffering

`stdin_pending` is a byte buffer that handles partial reads. A single 64 KB
chunk may contain hundreds of lines — all are dispatched in one batch with
`SetUpdatesEnabled(false)` / `SetUpdatesEnabled(true)` bracketing to avoid
per-line repaints.

On EOF, `flushTrailingLine` (in `src/ui/callbacks/piped.zig`) handles a
trailing line without `\n`.

## Cleanup

`QSocketNotifier` is a Qt child of the main widget — auto-deleted on close.
Owned strings in `piped_items` and `stdin_pending` are freed in
`AppState.deinit()` (in `src/state/app_state.zig`).

## Source Files

| File                                  | Purpose                                              |
| ------------------------------------- | ---------------------------------------------------- |
| `src/app/startup.zig`                 | `prepareInitialFrame` — installs the notifier        |
| `src/ui/callbacks/piped.zig`          | `onStdinActivated`, `appendBytes`, `appendLine`, `flushTrailingLine` |
| `src/ui/piped_view.zig`               | `appendPipedItem`, `renderPipedAppendBatch`          |

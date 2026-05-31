# Piped Mode

Data is streamed from stdin via `QSocketNotifier` — the window appears
immediately and items arrive asynchronously. The user can filter before all
lines have arrived.

## How it works

1. Window shows "Waiting for input..."
2. `QSocketNotifier` watches `STDIN_FILENO` via Qt's event loop
3. When data arrives, `onStdinActivated` reads up to 64 KB
4. Raw bytes accumulate in `stdin_pending`, split on `\n`
5. Complete lines are trimmed and added to the list immediately
6. On EOF: flush remaining bytes, disable notifier

## Buffering

`stdin_pending` is a byte buffer that handles partial reads. A single 64 KB
chunk may contain hundreds of lines — all are dispatched in one batch with
`SetUpdatesEnabled` batching to avoid per-line repaints.

On EOF, `flushPendingStdinLine` handles a trailing line without `\n`.

## Cleanup

`QSocketNotifier` is a Qt child of `main_widget` — auto-deleted on close.
Owned strings in `piped_items` and `stdin_pending` are freed in
`AppState.deinit()`.

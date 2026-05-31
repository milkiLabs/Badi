# Performance

Three techniques keep Badi responsive with 100k+ items:

## `SetUpdatesEnabled` batching

Qt repaints the `QListWidget` after every `SetRowHidden` or `AddItem2` call.
Wrapping loops with `SetUpdatesEnabled(false/true)` suppresses all intermediate
paints and triggers a single repaint at the end. Applied to:

- `filterList` — 10k hide/show calls → 1 repaint
- `rebuildList` — N item additions → 1 repaint
- `appendStdinBytes` — batch line appends → 1 repaint

## Zero-allocation streaming

`appendPipedItem` adds lines as-is without checking the current filter query.
Filtering happens lazily on the next keystroke via `filterList`. This avoids
allocating and freeing a string per line during high-throughput stdin reads.

## Fixed row heights

`SetUniformItemSizes(true)` tells Qt every row is the same height. Qt skips
per-item size measurement during layout, which speeds up scrolling and initial
rendering.

## Result

| Metric                             | Value |
| ---------------------------------- | ----- |
| Repaints per keystroke (10k items) | 1     |
| Allocations per 64 KB stdin batch  | 0     |
| Repaints per 64 KB stdin batch     | 1     |

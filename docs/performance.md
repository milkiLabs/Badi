# Performance

Three techniques keep Badi responsive with large result sets:

## Virtualized result rendering

Badi keeps filtering state in Zig and renders only a capped slice of matching
rows into `QListWidget`. The full result set lives in the source arrays:

- `visible_indices` stores matching source row indexes
- `selected_index` points into `visible_indices`
- `QListWidget` receives at most 128 rows around the current selection

This avoids creating a Qt item for every source row and avoids per-row
`SetRowHidden` calls while typing.

## Streaming append

Piped input is still stored as owned lines in `piped_items`. When a new line
arrives, Badi checks it against the active query and appends only the matching
source index to `visible_indices`.

## Fixed Row Heights

`SetUniformItemSizes(true)` tells Qt every rendered row is the same height. Qt
skips per-item size measurement during layout, which speeds up scrolling and
rendering.

## Result

| Metric                              | Value |
| ----------------------------------- | ----- |
| Qt rows per render                  | <=128 |
| Per-keystroke source scan           | O(N)  |
| Per-keystroke Qt item churn         | O(1)  |
| Per-row hide/show calls while typing | 0     |

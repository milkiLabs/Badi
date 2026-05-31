# Performance

Three techniques keep Badi responsive with large result sets:

## Qt Model-View Rendering

Badi uses `QListView` with a custom `QAbstractListModel`. The full result set
lives in Zig arrays, and Qt asks the model for only the rows it needs to paint:

- `visible_indices` stores matching source row indexes
- `selected_index` points into `visible_indices`
- `onModelRowCount` returns the current visible row count
- `onModelData` returns a `QVariant` string for the requested row

This avoids creating a Qt item for every source row, avoids per-row
`SetRowHidden` calls while typing, and leaves viewport virtualization to Qt.

## Streaming append

Piped input is still stored as owned lines in `piped_items`. When a new line
arrives, Badi checks it against the active query and appends only the matching
source index to `visible_indices`.

## Fixed Row Heights

`SetUniformItemSizes(true)` tells Qt every rendered row is the same height. Qt
skips per-item size measurement during layout, which speeds up scrolling and
rendering.

## Result

| Metric                               | Value          |
| ------------------------------------ | -------------- |
| Persistent Qt item objects per row   | 0              |
| Per-keystroke source scan            | O(N)           |
| Per-keystroke Qt item churn          | 0              |
| Rows painted per frame               | viewport-bound |
| Per-row hide/show calls while typing | 0              |

# Performance

Three techniques keep Badi responsive with large result sets:

## Qt Model-View Rendering

Badi uses `QListView` with a custom `QAbstractListModel`. The full result set
lives in Zig arrays, and Qt asks the model for only the rows it needs to paint:

- `AppState.visible_indices` stores matching source row indexes
- `AppState.selected_index` points into `visible_indices`
- `ui.model.onModelRowCount` (in `src/ui/model.zig`) returns the current
  visible row count
- `ui.model.onModelData` returns a `QVariant` string for the requested row

This avoids creating a Qt item for every source row, avoids per-row
`SetRowHidden` calls while typing, and leaves viewport virtualization to Qt.

## Streaming append

Piped input is stored as owned lines in `AppState.piped_items`. When a new
line arrives (via the `QSocketNotifier` callback), `piped_view.appendPipedItem`
scores it against the active query and inserts the source index into
`visible_indices` at the correct sorted position — no full re-filter.

The filter step itself (`core.filter.filter`) is pure Zig: generic over the
source type via a comptime accessor, scored by `core.search`, and capped at
`core.search.max_results` (currently 50) per query.

## Fixed Row Heights

`list.SetUniformItemSizes(true)` (in `src/ui/factory.zig::build`) tells Qt
every rendered row is the same height. Qt skips per-item size measurement
during layout, which speeds up scrolling and rendering.

## Result

| Metric                               | Value          |
| ------------------------------------ | -------------- |
| Persistent Qt item objects per row   | 0              |
| Per-keystroke source scan            | O(N)           |
| Per-keystroke Qt item churn          | 0              |
| Rows painted per frame               | viewport-bound |
| Per-row hide/show calls while typing | 0              |

## Source Files

| File                       | Purpose                                              |
| -------------------------- | ---------------------------------------------------- |
| `src/core/filter.zig`      | Generic filter step, uses comptime accessor         |
| `src/core/search.zig`      | Scoring engine (substring, multi-token, acronym)     |
| `src/ui/view.zig`          | `applyFilter` — drives the filter + model reset     |
| `src/ui/model.zig`         | `onModelRowCount`, `onModelData` (QAbstractListModel) |
| `src/ui/piped_view.zig`    | `appendPipedItem` — incremental append for piped    |
| `src/ui/factory.zig`       | `SetUniformItemSizes(true)` (uniform row heights)    |

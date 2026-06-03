# Search Algorithm

Badi uses a simple substring-based scoring algorithm for fuzzy search.

Implementation: `src/core/search.zig` (scoring) + `src/core/filter.zig` (filter step)

## Matching

Queries are matched in order of priority:

1. **Substring match** — case-insensitive substring search. Score = `10000 - position`.
   - "fire" → "**fire**fox" (score 10000, prefix)
   - "iref" → "f**iref**ox" (score 9999, pos 1)

2. **Multi-token** — query split by whitespace, each token must appear as a substring
   in order. Score drops as tokens are farther apart.
   - "web cam" → "**Web** **Cam**era"
   - "cam web" → "Web Camera" ❌ (out of order)

3. **Acronym** — first letters of each word in the candidate form an acronym;
   query must be a prefix of it. Score = 5000.
   - "gm" → "**G**oogle **M**aps"
   - "ff" → "**F**ast **F**ox"

## Result Limits

- Maximum **50 results** returned per search (`core.search.max_results`)
- Empty queries bypass scoring entirely and show all items in source order
  (in `apps` mode, the source order is replaced with a history-based
  ranking — see [launch-history](../launch-history.md))
- Ties break by source index (lower index first)

## Filter Step

`core.filter.filter` wraps the scorer and turns it into the format the UI
needs: a sorted, top-N list of source indices.

- `comptime T: type` — the source element type
- `comptime getText: fn (T) []const u8` — comptime accessor that returns
  the searchable string for an element. Avoids intermediate allocations
  for heterogeneous collections like `DesktopEntry[]`.
- Output is a slice of source indices in display order (best match first).

## Source Files

| File                       | Purpose                                              |
| -------------------------- | ---------------------------------------------------- |
| `src/core/search.zig`      | Scoring engine (`score`, `search`, `searchMapped`, `searchMappedBoosted`, `sortScored`), tests |
| `src/core/filter.zig`      | Generic filter step: source + query → top-N indices  |
| `src/core/launch_history.zig` | Per-app launch counts + `log2(count)` boost signal |
| `src/ui/view.zig`          | Integration: `applyFilter`, `fillApps` (history + boost wiring) |
| `src/ui/piped_view.zig`    | `appendPipedItem` (incremental piped append)         |

## Personal ranking (apps mode only)

On top of the base scoring, the apps list adds a small additive boost
based on how often you've launched each app. The boost is
`log2(launch_count)`, so a frequently-launched app is nudged by a
handful of points while a fresh app gets `0`. Base substring/acronym
scores are in the thousands, so the boost only matters when text
relevance is close — the user's typo-prone query still beats their
favourite app.

See [launch-history.md](../launch-history.md) for the storage format,
when the count is incremented, and why the signal is small.

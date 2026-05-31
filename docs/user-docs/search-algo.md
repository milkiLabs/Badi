# Search Algorithm

Badi uses a simple substring-based scoring algorithm for fuzzy search.

Implementation: `src/core/search.zig`

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

- Maximum **50 results** returned per search
- Empty queries bypass scoring entirely and show all items in source order

## Source Files

| File                  | Purpose                                          |
| --------------------- | ------------------------------------------------ |
| `src/core/search.zig` | Scoring engine, tests                            |
| `src/ui/window.zig`   | Integration: `filterList()`, `appendPipedItem()` |

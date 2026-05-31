# Search Algorithm

Badi uses a **hierarchical scoring algorithm** for fuzzy search.
It provides typo-tolerant, relevance-ranked results for both app names and piped input.

Implementation: `src/core/search.zig`

## Scoring Tiers

Results are ranked by a cascade of match types. The first matching tier determines
the base score. Within tiers, secondary penalties provide fine-grained ordering.

| Tier        | Score                       | Description                    | Example                          |
| ----------- | --------------------------- | ------------------------------ | -------------------------------- |
| Exact       | 10,000                      | query == candidate             | "firefox" = "firefox"            |
| Prefix      | 9,000 + quality             | candidate starts with query    | "fir" → "**fir**fox"             |
| Word Prefix | 8,500 + quality             | query at word boundary         | "map" → "Google **Map**s"        |
| Contains    | 7,500 - position            | substring anywhere             | "ire" → "F**ire**fox"            |
| Acronym     | 7,000                       | query = first letters of words | "gm" → "**G**oogle **M**aps"     |
| Token       | 6,700                       | all tokens found in text       | "web cam" → "**Web** **Cam**era" |
| Typo        | 5,900 - edits - length_diff | Levenshtein within tolerance   | "firefho" → "firefox"            |
| Subsequence | 5,400 - spread              | characters in order, scattered | "ffx" → "**F**ire**f**o**x**"    |

## Secondary Scoring

Within each tier, additional signals refine the ranking:

- **Prefix quality**: `max(0, 100 - (text.len - query.len))` — shorter names win
- **Contains position**: `- indexOf(query)` — earlier matches win
- **Typo penalty**: `- (distance × 160) - abs(text.len - query.len)` — fewer edits win
- **Subsequence spread**: `- (last_match - first_match - query.len)` — tighter clusters win

## Features

### Multi-Token Support

Space-separated tokens are each matched independently. All tokens must match for a
hit.

```
"web cam" → "Web Camera"    (both "web" and "cam" found)
"fire pad" → "Firefox"      (no match — "pad" not found)
```

### Acronym Matching

Build first-letter-of-each-word string. If the query matches the acronym start,
it's a hit.

```
"gm" → "Google Maps"   (acronym "GM", query matches prefix)
"wc" → "Word Counter"  (acronym "WC")
"ff" → "Fast Fox"      (acronym "FF")
```

### Typo Tolerance (Adaptive)

Levenshtein distance with an adaptive threshold based on query length:

| Query Length | Max Edits | Rationale                                 |
| ------------ | --------- | ----------------------------------------- |
| 1-2 chars    | 0         | Too many false positives on short queries |
| 3-5 chars    | 1         | Single typos only                         |
| 6+ chars     | 2         | Allow more flexibility on longer queries  |

Pre-filter: skips Levenshtein computation if `abs(query.len - token.len) > max_edits`.

### Subsequence Matching

If no higher tier matches, the algorithm checks if the query is a **subsequence** of
the candidate (characters appear in order, not necessarily adjacent). Matches with
tighter character clustering rank higher.

## Result Limits

- Maximum **50 results** returned per search
- Empty queries bypass scoring entirely and show all items in source order

## Performance

- **Per query-item pair**: O(N) single pass (N = candidate string length)
- **Levenshtein**: O(N × M) but only runs for queries >= 3 chars that failed higher tiers
- **Zero allocations** in the scoring function (all stack-allocated buffers)

## Source Files

| File                  | Purpose                                          |
| --------------------- | ------------------------------------------------ |
| `src/core/search.zig` | Scoring engine, Levenshtein, tests (444 lines)   |
| `src/ui/window.zig`   | Integration: `filterList()`, `appendPipedItem()` |
| `src/core_tests.zig`  | Test runner includes `search.zig` tests          |

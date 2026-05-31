Tier Score Description Example
Exact 10,000 query == candidate "firefox" = "firefox"
Prefix 9,000 + quality candidate starts with query "fir" → "firfox"
Word Prefix 8,500 + quality query at word boundary "map" → "Google Maps"
Contains 7,500 - position substring anywhere "ire" → "Firefox"
Acronym 7,000 query = first letters of words "gm" → "Google Maps"
Token 6,700 all tokens found in text "web cam" → "Web Camera"
Typo 5,900 - edits - length_diff Levenshtein within tolerance "firefho" → "firefox" (1 edit)
Subsequence 5,400 - spread characters in order, scattered "ffx" → "Firefox"

Secondary scoring within tiers:

- Prefix quality: max(0, 100 - (text.len - query.len)) — shorter names win
- Contains position: - indexOf(query) — earlier matches win
- Typo penalty: - (distance × 160) - abs(text.len - query.len) — fewer edits win
- Subsequence spread: - (last_match - first_match - query.len) — tighter clusters win
  Multi-token support: Space-separated tokens are each matched independently. "web cam" → "Web Camera" because "web" and "cam" are both found. All tokens must match for a hit.
  Acronym matching: Build first-letter-of-each-word string. "Google Maps" → "GM". If query matches acronym start, it's a hit.
  Typo tolerance (adaptive):
- Query length 1-2: no typo tolerance (too many false positives)
- Query length 3-5: max 1 edit (Levenshtein distance)
- Query length 6+: max 2 edits
- Pre-filter: skip Levenshtein if abs(query.len - token.len) > max_edits

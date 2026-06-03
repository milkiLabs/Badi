# Emoji Mode

Badi ships a built-in Unicode emoji picker. The data is pre-packed at build
time into a compact binary slab, embedded into the binary at compile time,
and queried via the same `core.filter` engine that powers apps search.

## Triggers

There are two ways to enter emoji mode:

| Trigger                | Type    | Notes                                                  |
| ---------------------- | ------- | ------------------------------------------------------ |
| `--emoji` on the CLI   | Initial | Show the picker when the window opens, no app scan.    |
| Typing `": "`          | Mid-session | Hardcoded trigger in apps mode. Clears the input.  |

The `": "` trigger is checked first in `onTextChanged`, before any
user-configured prefix trigger, so it's always available.

The two triggers are independent — you can run `badi --emoji` from a
keybinding, or use `badi` and start typing `": "`.

## CLI flags

| Flag       | Effect                                                                |
| ---------- | --------------------------------------------------------------------- |
| `--emoji`  | Enter emoji mode. Mutually exclusive with `--prompt`.                 |
| `--copy`   | Copy the selected glyph to the clipboard (the default action).       |
| `--print`  | Write the glyph to stdout and exit 0 (dmenu-style).                   |
| `--type`   | Synthesize keystrokes (wtype on Wayland, xdotool on X11).             |

Passing both `--emoji` and `--prompt` returns the `PromptAndEmojiExclusive`
error from `cli.parse`.

## Actions

When the user hits Enter on a selection, the configured action runs:

### `.copy` (default)

Tries external clipboard helpers in order:

1. `wl-copy` (from `wl-clipboard`) — spawn detached; it daemonizes
   and serves the clipboard after Badi exits.
2. **stdout fallback** — writes the glyph to stdout (dmenu-style) so
   the picker is still useful in a pipeline.

You need `wl-clipboard` installed.

### `.print`

Writes the glyph to stdout, no trailing newline, exit 0. Matches the
[dmenu convention](https://tools.skepticism.us/projects/dmenu/) — the
caller gets exactly the selected value.

### `.type_keys`

Synthesizes the glyph as keystrokes via `wtype -- <glyph>`. Requires
`wtype` to be installed.

Badi is itself focused while running, so we close Badi first; the
window manager restores focus to whatever app was focused before
Badi opened (the terminal, the text editor, etc.), and `wtype`
types the glyph there.

If `wtype` is not installed, falls back to the clipboard via
`.copy`.

## Data layout

The emoji data lives in `src/core/emoji/data/emoji.bin` (≈ 200 KB). The
file format is a hand-rolled little-endian slab:

```
┌────────────────── Header (16 bytes) ──────────────────┐
│ magic:   [4]u8    = "BMOJ"                             │
│ version: u32      = 1                                  │
│ count:   u32      = number of entries (no skin tones)  │
│ _reserved: u32    = 0                                  │
├────────────────── Blob (≈ 153 KB) ─────────────────────┤
│ glyph strings, name strings, joined                   │
│ "name kw1 kw2 ..." strings — back to back,            │
│ no null terminators.                                  │
│ Offsets in the records table are absolute file        │
│ positions (header is added at write time).            │
├────────────────── Records (N × 24 bytes) ──────────────┤
│ per-entry:                                            │
│   glyph_off: u32, glyph_len: u16, _pad: u16           │
│   name_off:  u32, name_len:  u16, _pad: u16           │
│   kw_off:    u32, kw_len:    u16, _pad: u16           │
├────────────────── Footer (4 bytes) ────────────────────┤
│ magic: [4]u8 = "JOMB" — guards against truncation.    │
│ Without the footer, a partial file would silently      │
│ mis-size the records table (the loader works           │
│ backwards from file end).                             │
└────────────────────────────────────────────────────────┘
```

The records table is the last section before the footer, so the loader
locates it by subtraction:
`records_start = file_size - footer_size - count * 24`, then verifies
the footer magic.

### Why 24 bytes per record?

C ABI padding. The trailing `u16` in each pair is padded to 4 bytes by
the struct alignment, even though the field itself is only 2 bytes. So
each record is 4+2+2+4+2+2+4+2+2 = 24 bytes. The generator and loader
both agree on this layout; the loader reads each field individually via
`std.mem.readInt` (no struct cast, no `@alignCast` traps, no extra
allocation).

### Why a slab and not JSON?

The full data set is ~200 KB of strings plus metadata. Parsing JSON at
startup is a few milliseconds of pure overhead that runs every launch.
The binary slab is `@embedFile`'d directly — no parse, no string
duplication, no allocation for the strings themselves. Only the
`EmojiEntry` slice (3 × pointer-size × count = ~46 KB on 64-bit) is
allocated at load time.

## Generation

The slab is generated by `scripts/gen-emoji.zig` from three vendored
sources (see `vendor/`):

| File                                | Source                                                            | Size  |
| ----------------------------------- | ----------------------------------------------------------------- | ----- |
| `vendor/unicode-emoji-by.json`      | [muan/unicode-emoji-json](https://github.com/muan/unicode-emoji-json) | 387 KB |
| `vendor/unicode-emoji-ordered.json` | CLDR emoji ordering                                                | 23 KB |
| `vendor/emojilib.json`              | [muan/emojilib](https://github.com/muan/emojilib)                  | 264 KB |

Regenerate with:

```bash
zig build gen-emoji
```

…or directly:

```bash
zig run scripts/gen-emoji.zig
```

The script is deterministic (sorts the records by their entry index
from the ordered JSON, not by JSON field order), so a re-run without
source changes produces an identical file. This is what gets committed
to the repo — the embedded blob does not need to be regenerated by
consumers.

## Skipping entries

The upstream `data-ordered-emoji.json` is the Unicode `emoji-test.txt`
derivation that ships skin-tone variants as separate entries. The
loader does **not** filter them — they're already absent from the
vendored file (muan's `data-by-emoji.json` only contains the base
emoji). When the Unicode consortium adds new emoji, regenerate from
upstream and they will appear automatically; skin tones are explicitly
left out of v1 per the design decision recorded in the project notes.

Pure-punctuation keywords from emojilib (e.g. `:D`, `:)`) are skipped
at generation time because they don't help a real search query.

## Fonts

Badi does not bundle any fonts. The picker works correctly only if a
color emoji font is installed and Qt's font fallback finds it. On
common distros this is `noto-fonts-emoji` (Arch) /
`fonts-noto-color-emoji` (Debian) / `google-noto-emoji-color-fonts`
(Fedora). Without it, glyphs render as boxes or generic monochrome
shapes.

## Performance

- 1894 entries (no skin tone variants; the upstream `emoji-test.txt`
  list minus duplicates the generator drops), ~46 KB of `EmojiEntry`
  slice (3 pointers × 1894 on 64-bit).
- The blob is in `.rodata` (no allocation, no copy).
- Search uses the same `core.filter.filter` as apps mode — bounded at
  50 results (`search.max_results`).
- Slab is loaded eagerly in `buildState` for any non-prompt mode
  (~30 KB allocation), so the `": "` trigger feels instant.

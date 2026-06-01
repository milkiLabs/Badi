# Vendored Data

The files in this directory are data sources used to generate
`src/core/emoji/data/emoji.bin` at build time.

## Regeneration

The generator lives at `scripts/gen-emoji.zig` and is run by
`zig build gen-emoji`. To pick up new emoji or keyword changes:

1. Refresh the vendored files from upstream.
2. Run `zig build gen-emoji`.
3. Commit the regenerated `src/core/emoji/data/emoji.bin`.

The generator is deterministic (it iterates the ordered JSON, not the
JSON field order), so re-running without source changes produces an
identical blob.

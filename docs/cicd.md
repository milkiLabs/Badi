# CI/CD

A GitHub Actions workflow automatically builds a release-optimized binary
whenever a version tag is pushed. The workflow lives at
`.github/workflows/release.yml`.

## Trigger

Any tag matching `v*` starts the workflow:

```bash
git tag v1.0.0
git push --tags
```

## Zig version

The workflow does not pin a specific Zig version — the `mlugg/setup-zig` step
omits `version`, so the action reads `minimum_zig_version` from
`build.zig.zon` (currently 0.16.0) and falls back to `latest`. To pin a
specific version, add it explicitly:

```yaml
- uses: mlugg/setup-zig@v2
  with:
    version: 0.13.0
```

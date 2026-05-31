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

The workflow uses `version: latest` to always pull the latest stable Zig
release. To pin a specific version, change it in the workflow:

```yaml
- uses: mlugg/setup-zig@v2
  with:
    version: 0.13.0
```

If you leave `version` empty, the action reads `minimum_zig_version` from
`build.zig.zon` and falls back to `latest`. This project currently requires
Zig 0.16.0, but mirrors may not yet carry nightly/dev builds — using
`latest` is the safest option.

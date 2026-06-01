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

The workflow uses `mlugg/setup-zig@v2` without a `version` argument, so the
action reads `minimum_zig_version` from `build.zig.zon` (currently 0.16.0)
and uses the latest matching release. To pin a specific version, add it
explicitly:

```yaml
- uses: mlugg/setup-zig@v2
  with:
    version: 0.16.0
```

## Qt version

The workflow installs Qt 6.8.3 via `jurplel/install-qt-action@v4` (target:
`desktop`, with system deps).

## Build command

```yaml
zig build -Doptimize=ReleaseFast -Dqt6-extra-path=$QT_ROOT_DIR -Dqt6-lib-path=$QT_ROOT_DIR/lib
```

The result is a `badi-linux-x86_64.tar.gz` archive attached to the GitHub
Release.

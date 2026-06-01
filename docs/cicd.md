# CI/CD

Two independent GitHub Actions workflows build the release artifacts
on every pushed `v*` tag. They run in parallel and each writes a
single file to the GitHub Release.

| Workflow                              | Produces                                    |
| ------------------------------------- | ------------------------------------------- |
| `.github/workflows/release.yml`       | `badi-linux-x86_64.tar.gz` (bare binary)    |
| `.github/workflows/appimage-release.yml` | `Badi-<tag>-x86_64.AppImage` (self-contained) |

The bare tarball is for distribution channels (AUR, package managers)
that prefer to depend on the system Qt. The AppImage is the
recommended option for end users — no system Qt install required.

A more detailed walkthrough of the AppImage build is in
[appimage.md](appimage.md).

## Trigger

Both workflows fire on the same event — pushing a tag that matches
`v*`:

```bash
git tag v1.0.0
git push --tags
```

Because the two workflows are independent, they run in parallel. The
GitHub Release ends up with both files because each workflow calls
`softprops/action-gh-release@v2` with its own `files:` entry —
`softprops` adds the file to the existing release rather than
recreating it.

## Toolchain

Both workflows use the same toolchain pinning:

| Tool      | Version | Source                                |
| --------- | ------- | ------------------------------------- |
| Zig       | ≥ 0.16.0 | `mlugg/setup-zig@v2` (reads `minimum_zig_version` from `build.zig.zon`) |
| Qt        | 6.8.3   | `jurplel/install-qt-action@v4` (target: `desktop`, with system deps) |
| Zig build | `zig build -Doptimize=ReleaseFast -Dqt6-extra-path=$QT_ROOT_DIR -Dqt6-lib-path=$QT_ROOT_DIR/lib` | |

## `release.yml` — bare tarball

Builds the binary with `zig build`, tars it as
`badi-linux-x86_64.tar.gz`, and uploads both:

- as a GitHub Actions artifact (`name: release-<tag>`, path: `zig-out/`)
- as a release asset on the GitHub Release

The tarball does not bundle any libraries. The user is expected to
have Qt 6 (`qt6-base` on most package managers) and `gcc-libs`
installed.

## `appimage-release.yml` — AppImage

In addition to the standard toolchain, this workflow uses the
following env vars (set at the job level, inherited by every step):

```yaml
env:
  APPIMAGE_EXTRACT_AND_RUN: 1          # run AppImage tools without FUSE
  QML_SOURCES_PATHS: ""                # Badi has no QML
  DISABLE_PLUGIN_QT_TRANSLATIONS: "1"  # skip qt_*.qm
  LINUXDEPLOY_OUTPUT_VERSION: ${{ github.ref_name }}  # embed tag in filename
  NO_STRIP: "1"                        # work around old bundled strip
```

`QMAKE`, `QTDIR`, and the `PATH` override are set on the
**"Build AppImage" step itself**, not at the job level, because
they depend on `QT_ROOT_DIR` which is only exported by the
`install-qt-action` step (i.e. after job-level env is processed).
Setting them at job level triggers a "Unrecognized named-value:
'env.QT_ROOT_DIR'" static-analysis error.

### AppImage-specific steps

After the standard `zig build`, the workflow runs:

1. **Stage AppImage** — copies `zig-out/bin/badi`, `assets/badi.desktop`,
   and the icon assets into an `AppDir/` tree that mirrors a FHS
   install.
2. **Download linuxdeploy tools** — fetches
   `linuxdeploy-x86_64.AppImage`, `linuxdeploy-plugin-qt-x86_64.AppImage`,
   and `appimagetool-940-x86_64.AppImage` from the upstream
   `continuous` releases, `chmod +x` them, then creates short-name
   symlinks (`linuxdeploy`, `linuxdeploy-plugin-qt`, `appimagetool`)
   so the binaries can be invoked by basename via `PATH`.
3. **Build AppImage** — sets `QTDIR`, `QMAKE`, and the `PATH` override
   on the step, then runs `linuxdeploy` with `--plugin qt
   --output appimage` to bundle the Qt 6 libraries and platform
   plugins and repack the AppDir as a squashfs AppImage.
4. **Verify AppImage** — sanity-checks the file with `ls` + `file`.
5. **Upload artifact** — as a GitHub Actions artifact
   (`name: Badi-<tag>-x86_64`).
6. **GitHub Release** — attaches the AppImage to the release.

### Why these env vars are set

| Var                                | Reason                                                                                                                                                       |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `APPIMAGE_EXTRACT_AND_RUN=1`       | The `ubuntu-latest` runner does not have FUSE; this lets the linuxdeploy and appimagetool AppImages self-extract.                                            |
| `QML_SOURCES_PATHS=""`             | Badi is QML-free; clearing the var avoids a wasted scan for QML imports.                                                                                     |
| `DISABLE_PLUGIN_QT_TRANSLATIONS=1` | Saves several MB by skipping `qt_*.qm` files (Badi is English-only).                                                                                         |
| `LINUXDEPLOY_OUTPUT_VERSION`       | Embeds the tag in the AppImage filename so `Badi-v1.0.0-x86_64.AppImage` lands in the release.                                                                |
| `NO_STRIP=1`                       | The `strip` bundled inside the linuxdeploy AppImage is too old to handle the `.relr.dyn` ELF section used by current glibc-built libraries.                |
| `QMAKE` *(step-level)*             | Forces `linuxdeploy-plugin-qt` to query the correct `qmake`. Without this it may silently pick up a Qt5 `qmake` from the runner's `PATH`.                  |
| `QTDIR` *(step-level)*             | Standard convention; some tools look for `$QTDIR/bin/qmake`. The plugin already prefers `$QMAKE` when set.                                                  |
| `PATH` override *(step-level)*     | Prepends `$QT_ROOT_DIR/bin` and `$GITHUB_WORKSPACE/tools` so `qmake6` / `moc` and the linuxdeploy binaries are resolved by basename.                       |

## Pinning the linuxdeploy versions

Both workflows pull from the upstream `continuous` rolling releases.
For a fully reproducible build, pin each tool to a specific tag —
e.g. `1-alpha-20251107-1` for linuxdeploy and a specific
`appimagetool-<N>` build for `appimagetool`. See
[appimage.md#gotchas-discovered-while-building](appimage.md#gotchas-discovered-while-building)
for the rationale.

## Local equivalents

The CI pipelines have direct local counterparts. See
[appimage.md](appimage.md) for the AppImage side, and the
[Building section of the README](../README.md#building) for the
tarball side.

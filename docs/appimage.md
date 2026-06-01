# AppImage

Badi ships a portable, single-file AppImage alongside the bare tarball.
The AppImage bundles `badi` together with the Qt 6 runtime libraries
(`Qt6Core`, `Qt6Gui`, `Qt6Widgets`, `Qt6DBus`, and the Xcb platform
plugin) and resolves them via `$ORIGIN`-relative RPATH at runtime.
End users only need `glibc`, `libstdc++`, `libm`, and `libz` from the
host.

## What gets bundled

```
Badi-<version>-x86_64.AppImage
├── AppRun           → usr/bin/badi
├── badi.desktop
├── badi.png         → usr/share/icons/hicolor/256x256/apps/badi.png
└── usr/
    ├── bin/badi
    ├── lib/         (83 shared libraries: Qt6, glib, icu, xcb, …)
    └── share/
        ├── applications/badi.desktop
        └── icons/hicolor/{256x256,512x512}/apps/badi.png
```

The result is ~42 MB compressed, ~117 MB unpacked (squashfs compresses
the .so files well).

## Prerequisites

To build an AppImage locally you need everything required to build
`badi` from source, plus a few extra tools:

| Tool                  | Why                                                     | Install (Arch)            | Install (Debian/Ubuntu)         |
| --------------------- | ------------------------------------------------------- | ------------------------- | ------------------------------- |
| Zig ≥ 0.16.0          | Compiles `badi`                                          | `pacman -S zig`           | download from ziglang.org       |
| Qt 6 dev headers      | Compiles `badi` (Core, Gui, Widgets)                     | `pacman -S qt6-base`      | `apt install qt6-base-dev`     |
| `gcc`                 | Resolves `libstdc++` at link time                        | `pacman -S gcc`           | `apt install gcc`               |
| `librsvg2-bin`        | Renders the `.svg` icon to `.png`                        | `pacman -S librsvg`       | `apt install librsvg2-bin`      |
| FUSE                  | Lets the AppImage tools run as AppImages on your system | `pacman -S fuse2`         | `apt install libfuse2`          |
| `curl`                | Downloads the linuxdeploy tools                         | `pacman -S curl`          | `apt install curl`              |

> If FUSE is unavailable (e.g. inside a container without `/dev/fuse`),
> the linuxdeploy and appimagetool AppImages still run when
> `APPIMAGE_EXTRACT_AND_RUN=1` is set in the environment. The release
> workflow relies on this.

## Build pipeline

The release workflow runs three steps to produce the AppImage: stage
the AppDir, download the linuxdeploy tools, run `linuxdeploy` with the
Qt plugin. The same sequence works locally.

### 1. Build the binary

```bash
zig build -Doptimize=ReleaseFast
```

Output: `zig-out/bin/badi`.

### 2. Stage the AppDir

The AppDir is a self-contained directory tree that mirrors a FHS
installation. linuxdeploy inspects it, fills in the missing libraries
and Qt plugins, then repacks it as an AppImage.

```bash
mkdir -p AppDir/usr/bin
mkdir -p AppDir/usr/share/applications
mkdir -p AppDir/usr/share/icons/hicolor/256x256/apps
mkdir -p AppDir/usr/share/icons/hicolor/512x512/apps

install -Dm755 zig-out/bin/badi            AppDir/usr/bin/badi
install -Dm644 assets/badi.desktop         AppDir/usr/share/applications/badi.desktop
install -Dm644 assets/badi-256.png         AppDir/usr/share/icons/hicolor/256x256/apps/badi.png
install -Dm644 assets/badi-512.png         AppDir/usr/share/icons/hicolor/512x256/apps/badi.png
install -Dm644 assets/badi.desktop         AppDir/badi.desktop
```

The desktop file and icon are duplicated at the AppDir root because
linuxdeploy's appimage output plugin picks up the entry-point files
from there.

### 3. Download the linuxdeploy tools

```bash
mkdir -p tools && cd tools

curl -fsSL -o linuxdeploy.AppImage \
  https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage

curl -fsSL -o linuxdeploy-plugin-qt.AppImage \
  https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage

curl -fsSL -o appimagetool.AppImage \
  https://github.com/probonopd/go-appimage/releases/download/continuous/appimagetool-940-x86_64.AppImage

chmod +x *.AppImage

# Short-name symlinks so the binaries can be invoked by basename.
# The upstream artifacts always carry the `.AppImage` suffix.
ln -sf linuxdeploy.AppImage         linuxdeploy
ln -sf linuxdeploy-plugin-qt.AppImage linuxdeploy-plugin-qt
ln -sf appimagetool.AppImage        appimagetool
```

> The asset name for `appimagetool` includes a build number suffix
> (`appimagetool-940-x86_64.AppImage`). The old name
> (`appimagetool-x86_64.AppImage` from the archived `AppImageKit`
> repo) returns 404 — the project moved to `probonopd/go-appimage`.

### 4. Run linuxdeploy

```bash
export APPIMAGE_EXTRACT_AND_RUN=1
export QML_SOURCES_PATHS=""
export DISABLE_PLUGIN_QT_TRANSLATIONS=1
export LINUXDEPLOY_OUTPUT_VERSION="v1.0.0-local"
export QMAKE="$(qmake6 -query QT_INSTALL_BINS)/qmake6"
export QTDIR="$(qmake6 -query QT_INSTALL_PREFIX)"
export NO_STRIP=1
export PATH="$QTDIR/bin:$PWD/tools:$PATH"

linuxdeploy \
  --appdir AppDir \
  --executable AppDir/usr/bin/badi \
  --desktop-file AppDir/badi.desktop \
  --icon-file AppDir/usr/share/icons/hicolor/256x256/apps/badi.png \
  --plugin qt \
  --output appimage
```

The output file is `Badi-v1.0.0-local-x86_64.AppImage` (named from
`Name=Badi` in the desktop file plus the `LINUXDEPLOY_OUTPUT_VERSION`
and arch).

## Verification

Quick checks you can run on the produced file:

```bash
# File type
file Badi-v1.0.0-local-x86_64.AppImage
# → ELF 64-bit LSB pie executable, x86-64, … (AppImage type 2)

# Mount + inspect the AppImage squashfs
./Badi-v1.0.0-local-x86_64.AppImage --appimage-extract
ls squashfs-root/
ls squashfs-root/usr/lib/ | wc -l        # → 80+ shared libraries

# Confirm the binary resolves Qt deps to the AppImage's usr/lib
LD_LIBRARY_PATH=$PWD/squashfs-root/usr/lib \
  ldd squashfs-root/usr/bin/badi | head
# → libQt6Core.so.6 => .../squashfs-root/usr/lib/libQt6Core.so.6

rm -rf squashfs-root
```

If the app is bundled correctly, the only libraries still resolved
from `/usr/lib` should be `libc`, `libm`, `libstdc++`, and `libz` —
all of which the AppImage intentionally leaves to the host (per the
AppImage convention).

## Environment variables explained

| Variable                          | Why it's set                                                                                                                                              |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `APPIMAGE_EXTRACT_AND_RUN=1`      | Lets the linuxdeploy / appimagetool AppImages self-extract on hosts without FUSE (most CI runners).                                                       |
| `QML_SOURCES_PATHS=""`            | Badi doesn't use QML, but the Qt plugin walks this path for QML imports. Clearing it skips the scan.                                                       |
| `DISABLE_PLUGIN_QT_TRANSLATIONS=1`| Skips bundling the `*.qm` translation files. They are unused (Badi is English-only) and account for several MB.                                           |
| `LINUXDEPLOY_OUTPUT_VERSION`      | Embedded in the AppImage filename and inside the AppImage metadata. The release workflow sets this to the git tag (e.g. `v1.0.0`).                       |
| `QMAKE`                           | Forces `linuxdeploy-plugin-qt` to query a specific `qmake` binary. **Required** if a system Qt5 is also installed and shadows Qt6 in `$PATH`.            |
| `QTDIR`                           | Standard convention; some tools (and older versions of the Qt plugin) look for `$QTDIR/bin/qmake`. The plugin already prefers `$QMAKE` when set.        |
| `NO_STRIP=1`                      | The `strip` binary bundled inside the linuxdeploy AppImage is too old to understand the `.relr.dyn` ELF section used by current glibc-built libraries.  |

## Gotchas discovered while building

These are the things that broke on a first attempt, recorded here so
the next person doesn't have to rediscover them:

1. **`URL=` in a `Type=Application` desktop file is invalid.** The
   field is only allowed on `Type=Link`. `appimagetool` will refuse
   the build. Either remove the field or change the type.

2. **More than one main category in `Categories=`** (e.g.
   `Utility;System;`) prints a warning from `appimagetool` because
   the resulting desktop entry may appear twice in the application
   menu. Use a single main category plus any number of additional
   ones: `Utility;` is fine.

3. **`linuxdeploy-plugin-qt` finds the wrong `qmake`.** It uses
   whichever `qmake` is first in `$PATH`, so on systems with Qt5
   installed, it silently queries Qt5 paths and fails with
   `ERROR: Could not find Qt modules to deploy`. Set
   `QMAKE=<path-to-qmake6>` explicitly.

4. **Old bundled `strip` chokes on `.relr.dyn`.** The `strip` from
   the AppImage runtime is older than the binutils that built the
   system's shared libraries, so it errors on `.relr.dyn` and
   `linuxdeploy` exits non-zero. Set `NO_STRIP=1`.

5. **`appimagetool` moved.** The old
   `AppImageKit/AppImageKit` repo is archived; the new home is
   `probonopd/go-appimage`, and the asset name now includes a
   build-number suffix. A bare `appimagetool-x86_64.AppImage` URL
   404s.

6. **PATH order matters for `QMAKE` discovery.** Even with
   `QMAKE=/usr/lib/qt6/bin/qmake6` set as an env var, also put
   `$QTDIR/bin` first in `PATH` so the plugin can also locate
   `moc`, `rcc`, and the Xcb platform plugin correctly.

7. **Upstream artifacts always have the `.AppImage` suffix, so
   `PATH` lookup by basename fails.** The downloads land as
   `tools/linuxdeploy.AppImage`, `tools/linuxdeploy-plugin-qt.AppImage`,
   and `tools/appimagetool.AppImage`. If the next step does
   `linuxdeploy --appdir …` and `tools/` is in `PATH`, the shell
   reports `linuxdeploy: command not found` (exit 127) because
   `linuxdeploy` is not the actual filename. Either invoke with
   the full `.AppImage` suffix or create short-name symlinks
   (`ln -sf linuxdeploy.AppImage linuxdeploy`). The CI workflow
   does the latter, and so does the local recipe in step 3.

8. **`QMAKE` (and any other var derived from `QT_ROOT_DIR`) cannot
   be set in the job-level `env:` block.** GitHub Actions validates
   `env.*` expressions statically and `QT_ROOT_DIR` is exported by
   the `install-qt-action` *step* — so at job-level it doesn't
   exist yet, and the workflow file is rejected with
   `Unrecognized named-value: 'env'`. Set these vars on the step
   that actually uses them (the "Build AppImage" step in our case).

## Tools used

- [linuxdeploy](https://github.com/linuxdeploy/linuxdeploy) — generic
  AppImage bundler. Detects the binary's shared library dependencies
  and copies them into the AppDir.
- [linuxdeploy-plugin-qt](https://github.com/linuxdeploy/linuxdeploy-plugin-qt) —
  pulls in the Qt 6 platform plugin (`libqxcb`), `libQt6DBus`, and
  any other Qt modules the binary actually uses.
- [appimagetool](https://github.com/probonopd/go-appimage) —
  repacks the AppDir into a self-mounting squashfs AppImage.
- [libqt6zig](https://github.com/rcalixte/libqt6zig) — Zig bindings
  for Qt 6, linked statically into `badi` itself (so it does **not**
  need to be bundled into the AppImage; only the underlying Qt 6
  C++ `.so` files are).

## See also

- [cicd.md](cicd.md) — both release workflows; the AppImage one
  lives at `.github/workflows/appimage-release.yml`.
- [assets/badi.desktop](../assets/badi.desktop) — the desktop entry
  that ships inside the AppImage.
- [assets/badi.svg](../assets/badi.svg) — the icon source.

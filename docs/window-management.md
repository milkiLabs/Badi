# Window Management

Badi is a launcher that needs to behave like a system overlay: always
on top, always centered, always keyboard-focused. How that is achieved
depends on the display server.

---

## Wayland (primary path)

On a Wayland session, Qt's portable window hints (`WindowStaysOnTopHint`,
`Dialog`, etc.) are meaningless — the compositor ignores them. Badi
uses the **wlr-layer-shell** Wayland protocol instead, via the
`LayerShellQt` library bundled with KDE Plasma / wlroots compositors.

### Protocol overview

wlr-layer-shell lets a client request a "layer surface" — a special
surface that the compositor places on a named layer:

| Layer       | Typical use          |
| ----------- | -------------------- |
| `background`| wallpapers           |
| `bottom`    | desktop widgets      |
| `top`       | panels, taskbars     |
| `overlay`   | lock screens, launchers ← Badi |

Surfaces on `overlay` sit above every application window regardless
of which workspace or output they are on.

### Session detection

`badi_is_wayland_session()` in [`src/wayland_layer_shell.cpp`](../src/wayland_layer_shell.cpp)
checks two environment variables:

```
XDG_SESSION_TYPE == "wayland"   (set by the login manager)
WAYLAND_DISPLAY  != ""          (set by the compositor)
```

If either is true the Wayland path is taken.

### Layer surface setup

[`src/ui/wayland.zig`](../src/ui/wayland.zig) calls `setup(widget)` in
`App.run`, just before `Show()`:

```zig
ui.wayland.setup(self.state.ui.main);
self.state.ui.main.Show();
```

`setup` does three things:

1. **`widget.CreateWinId()`** — forces Qt to allocate the underlying
   `QWindow` platform handle before the widget is shown. Without this,
   `WindowHandle()` returns a null pointer.

2. **`widget.WindowHandle()`** — retrieves the `QWindow*` and passes it
   to the C++ shim.

3. **`badi_layer_shell_setup(qwindow, width, height)`** — configures
   the layer surface:

```cpp
l_window->setLayer(LayerShellQt::Window::LayerOverlay);
l_window->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityExclusive);
l_window->setWantsToBeOnActiveScreen(true);
l_window->setAnchors(static_cast<LayerShellQt::Window::Anchor>(0)); // AnchorNone
l_window->setDesiredSize(QSize(width, height));
```

| Setting                        | Value                        | Effect |
| ------------------------------ | ---------------------------- | ------ |
| `Layer`                        | `LayerOverlay`               | Floats above every app window |
| `KeyboardInteractivity`        | `KeyboardInteractivityExclusive` | Compositor routes all keyboard input here; no focus-stealing timer needed |
| `WantsToBeOnActiveScreen`      | `true`                       | Appears on whatever output the user is currently looking at |
| `Anchors`                      | `0` (none)                   | No edge anchoring → compositor centers the surface |
| `DesiredSize`                  | `width × height` from widget | Centers at exactly the configured window size |

The `AnchorNone` + `DesiredSize` combination is the key to centering.
When no anchors are set the wlr-layer-shell spec says the compositor
MUST place the surface at the center of the output, sized to
`desiredSize`. Without `desiredSize`, the compositor would stretch the
surface to fill the entire output.

### Why no focus guard?

On X11 (and in early Badi versions) a `QTimer` fired every 75 ms to
call `Raise()` + `ActivateWindow()` + `SetFocus()` to keep the input
responsive. On Wayland this is both unnecessary and forbidden:

- `KeyboardInteractivityExclusive` guarantees the compositor delivers
  all key events to the layer surface for as long as it is visible.
- Compositors enforce their own input routing; application-side focus
  grabbing is a protocol error.

The timer, the `onFocusGuardTimeout` callback, and `onInputFocusOut`
have been removed entirely.

---

## X11 (fallback path)

When `badi_is_wayland_session()` returns `false`, Badi falls back to
standard Qt window hints set in [`src/ui/factory.zig`](../src/ui/factory.zig):

```zig
qt6.qnamespace_enums.WindowType.Dialog |
qt6.qnamespace_enums.WindowType.FramelessWindowHint |
qt6.qnamespace_enums.WindowType.WindowStaysOnTopHint
```

| Flag                    | Effect |
| ----------------------- | ------ |
| `Dialog`                | Tells the WM to treat this as a transient dialog, not a regular window (no taskbar entry) |
| `FramelessWindowHint`   | Suppresses the WM titlebar and border |
| `WindowStaysOnTopHint`  | Requests the WM to keep the window above normal windows |

The layer shell setup step is skipped entirely on X11 (`wayland.setup`
returns early when `isWayland()` is false).

---

## Relevant files

| File | Role |
| ---- | ---- |
| [`src/wayland_layer_shell.cpp`](../src/wayland_layer_shell.cpp) | C++ shim: session detection + `LayerShellQt` configuration |
| [`src/ui/wayland.zig`](../src/ui/wayland.zig) | Zig wrapper: `extern "C"` declarations + `setup(widget)` |
| [`src/ui/factory.zig`](../src/ui/factory.zig) | Chooses Qt window flags based on session type, calls `SetFixedSize2` |
| [`src/app/mod.zig`](../src/app/mod.zig) | Calls `wayland.setup` then `Show` in `App.run` |
| [`build.zig`](../build.zig) | Links `LayerShellQtInterface`, compiles the C++ shim with `link_libcpp` |

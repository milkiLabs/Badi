#include <QWindow>
#include <QSize>
#include <LayerShellQt/window.h>
#include <cstdlib>
#include <cstring>

extern "C" {

bool badi_is_wayland_session() {
    const char* session_type = std::getenv("XDG_SESSION_TYPE");
    if (session_type && std::strcmp(session_type, "wayland") == 0) {
        return true;
    }
    const char* wayland_display = std::getenv("WAYLAND_DISPLAY");
    if (wayland_display && std::strlen(wayland_display) > 0) {
        return true;
    }
    return false;
}

void badi_layer_shell_setup(void* qwindow_ptr, int width, int height) {
    if (!qwindow_ptr) return;
    QWindow* window = static_cast<QWindow*>(qwindow_ptr);
    
    LayerShellQt::Window* l_window = LayerShellQt::Window::get(window);
    if (!l_window) return;
    
    l_window->setLayer(LayerShellQt::Window::LayerOverlay);
    l_window->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityExclusive);
    l_window->setWantsToBeOnActiveScreen(true);

    // According to wlr-layer-shell: if no anchors are set, the surface is centered by the compositor.
    l_window->setAnchors(static_cast<LayerShellQt::Window::Anchor>(0));
    
    // Set the desired size so it centers at this size instead of taking the whole screen
    l_window->setDesiredSize(QSize(width, height));
}

}

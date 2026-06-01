// The C-ABI bridge. Qt signal callbacks cannot capture state, so the only
// way for them to access application state is through a global pointer.
// `set()` is called once at startup; `get()` is called from every callback.
//
// `get()` panics if the global is null. That's intentional: a null state
// during a Qt signal means startup ordering is wrong, and panicking is the
// fastest way to surface the bug.

const AppState = @import("app_state.zig").AppState;

var active: ?*AppState = null;

pub fn set(s: *AppState) void {
    active = s;
}

pub fn get() *AppState {
    return active.?;
}

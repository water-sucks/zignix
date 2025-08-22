const std = @import("std");

pub const util = @import("./util.zig");
pub const store = @import("./store.zig");
pub const expr = @import("./expr.zig");
pub const flake = @import("./flake.zig");
pub const NixError = @import("./error.zig").NixError;
pub const NixContext = util.NixContext;

/// Initialize the utils, store, and expr library's global
/// resources, in that order.
///
/// This obviates the need to call each init function manually
/// for each library.
///
/// This will also load settings values for the Nix store library.
pub fn init(context: *NixContext) !void {
    try util.init(context);
    try store.init(context, true);
    try expr.init(context);
}

test {
    std.testing.refAllDecls(@This());
}

const std = @import("std");

pub const expr = @import("./expr.zig");
pub const EvalState = expr.EvalState;
pub const EvalStateBuilder = expr.EvalStateBuilder;
pub const ValueType = expr.ValueType;
pub const NixValue = expr.Value;
pub const ListBuilder = expr.ListBuilder;
pub const BindingsBuilder = expr.BindingsBuilder;
pub const AttrsetIterator = expr.AttrsetIterator;
pub const RealisedString = expr.RealisedString;
pub const RealisedStringIterator = expr.RealisedStringIterator;
pub const gc = expr.gc;
pub const flake = @import("./flake.zig");
pub const FlakeSettings = flake.FlakeSettings;
pub const FlakeRefParseFlags = flake.FlakeRefParseFlags;
pub const FlakeLockFlags = flake.FlakeLockFlags;
pub const FlakeReference = flake.FlakeReference;
pub const LockedFlake = flake.LockedFlake;
pub const store = @import("./store.zig");
pub const NixStore = store.Store;
pub const RealisedPath = store.RealisedPath;
pub const StorePath = store.StorePath;
pub const Derivation = store.Derivation;
pub const util = @import("./util.zig");
pub const NixContext = util.NixContext;
pub const settings = util.settings;
pub const errors = @import("error.zig");
pub const NixError = errors.NixError;

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

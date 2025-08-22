const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

pub const libnix = @cImport({
    @cInclude("nix_api_util.h");
    @cInclude("nix_api_expr.h");
    @cInclude("nix_api_store.h");
    @cInclude("nix_api_value.h");
    @cInclude("nix_api_flake.h");
    @cInclude("nix_api_fetchers.h");
});

/// A container for retrieving and duplicating strings inside of Nix string
/// callbacks. Not meant for usage outside of this bindings library.
pub const StringDataContainer = struct {
    allocator: Allocator,
    result: ?[]u8,

    const Self = @This();

    pub fn new(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .result = null,
        };
    }
};

/// Retrive a string from the Nix callback and duplicate it for usage
/// on the Zig side. This function is meant to be used with a user_data
/// field that contains a type of StringDataContainer, and is not meant
/// for usage outside of this bindings library.
pub export fn genericGetStringCallback(
    start: [*c]const u8,
    n: c_uint,
    user_data: ?*anyopaque,
) callconv(.C) void {
    const data: *StringDataContainer = @ptrCast(@alignCast(user_data.?));

    const slice = start[0..n];
    data.result = data.allocator.dupe(u8, slice) catch null;
}

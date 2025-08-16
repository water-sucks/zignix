const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const testing = std.testing;

const c = @import("./c.zig");
const libnix = c.libnix;
const errors = @import("./error.zig");
const nixError = errors.nixError;
const NixError = errors.NixError;

/// Initialize libutil and its dependencies.
pub fn init(context: *NixContext) NixError!void {
    const err = libnix.nix_libutil_init(context.context);
    if (err != 0) return nixError(err);
}

/// Retrieve the current libnix library version.
pub fn version() []const u8 {
    return mem.span(libnix.nix_version_get());
}

pub const settings = struct {
    /// Retrieve a setting from the Nix global configuration.
    /// Caller owns returned memory.
    pub fn get(allocator: Allocator, context: *NixContext, key: []const u8) ![]u8 {
        const keyz = try allocator.dupeZ(u8, key);
        defer allocator.free(keyz);

        var data = c.StringDataContainer.new(allocator);

        const err = libnix.nix_setting_get(context.context, key.ptr, c.genericGetStringCallback, &data);
        if (err != 0) return nixError(err);

        return data.result orelse Allocator.Error.OutOfMemory;
    }

    /// Set a setting in the Nix global configuration.
    pub fn set(allocator: Allocator, context: *NixContext, key: []const u8, value: []const u8) !void {
        const keyz = try allocator.dupeZ(u8, key);
        defer allocator.free(keyz);

        const valuez = try allocator.dupeZ(u8, value);
        defer allocator.free(valuez);

        const err = libnix.nix_setting_set(context.context, keyz.ptr, valuez.ptr);
        if (err != 0) return nixError(err);
    }
};

/// Nix error state.
///
/// Use this to handle/diagnose errors from Nix code itself.
pub const NixContext = struct {
    /// The internal opaque context for storing Nix error messages.
    /// Do not touch unless you know what you are doing.
    context: *libnix.nix_c_context,
    allocator: Allocator,

    const Self = @This();

    /// Create an instance of NixContext.
    ///
    /// Caller must call deinit() to free memory with the underlying allocator.
    pub fn init(allocator: Allocator) !*Self {
        const new_context = libnix.nix_c_context_create();
        if (new_context == null) return error.OutOfMemory;

        const result = try allocator.create(Self);
        result.* = .{
            .allocator = allocator,
            .context = new_context.?,
        };

        return result;
    }

    /// Retrieve the most recent error code from this context.
    pub fn errorCode(self: Self) NixError!void {
        const err = libnix.nix_err_code(self.context);
        if (err != 0) return nixError(err);
    }

    /// Retrieve the error message from errorInfo inside another context.
    ///
    /// Used to inspect Nix error messages; only call after the previous
    /// Nix function has returned `NixError.NixError`.
    ///
    /// If an error is returned from here, this is likely not recoverable.
    ///
    /// Caller owns returned memory.
    pub fn errorInfoMessage(self: Self) ![]u8 {
        const scratch_context = try Self.init(self.allocator);
        defer scratch_context.deinit();

        var data = c.StringDataContainer.new(self.allocator);

        const err = libnix.nix_err_info_msg(null, self.context, c.genericGetStringCallback, &data);
        if (err != 0) return nixError(err);

        return data.result orelse Allocator.Error.OutOfMemory;
    }

    /// Retrieve the most recent error message directly from a context
    /// if it exists.
    ///
    /// If an error is returned from here, this is likely not recoverable.
    ///
    /// Caller does not own returned memory.
    pub fn errorMessage(self: Self) !?[]const u8 {
        const scratch_context = try Self.init(self.allocator);
        defer scratch_context.deinit();

        const message = libnix.nix_err_msg(null, self.context, null);
        return if (message) |m| mem.span(m) else null;
    }

    /// Retrieve the error name from a context.
    ///
    /// Used to inspect Nix error messages; only call after the previous
    /// Nix function has returned a `NixError.NixError`.
    ///
    /// If an error is returned from here, this is likely not recoverable.
    ///
    /// Caller owns returned memory.
    pub fn errorName(self: Self) ![]u8 {
        const scratch_context = try Self.init(self.allocator);
        defer scratch_context.deinit();

        var data = c.StringDataContainer.new(self.allocator);

        const err = libnix.nix_err_name(null, self.context, c.genericGetStringCallback, &data);
        if (err != 0) return nixError(err);

        return data.result orelse Allocator.Error.OutOfMemory;
    }

    /// Free the `NixContext`. Does not fail.
    pub fn deinit(self: *Self) void {
        libnix.nix_c_context_free(self.context);
        self.allocator.destroy(self);
    }
};

test "getting valid setting succeeds" {
    const context = try NixContext.init(testing.allocator);
    defer context.deinit();

    try init(context);

    const value = try settings.get(testing.allocator, context, "max-jobs");
    defer testing.allocator.free(value);
}

test "setting valid setting succeeds" {
    const context = try NixContext.init(testing.allocator);
    defer context.deinit();

    try init(context);

    try settings.set(testing.allocator, context, "max-jobs", "5");

    const actual = try settings.get(testing.allocator, context, "max-jobs");
    defer testing.allocator.free(actual);

    try testing.expectEqualStrings("5", actual);
}

test "getting invalid setting fails" {
    const context = try NixContext.init(testing.allocator);
    defer context.deinit();

    try init(context);

    try testing.expectError(error.Key, settings.get(testing.allocator, context, "nonexistent"));
}

test "setting invalid setting fails" {
    const context = try NixContext.init(testing.allocator);
    defer context.deinit();

    try init(context);

    try testing.expectError(error.Key, settings.set(testing.allocator, context, "nonexistent", "value"));
}

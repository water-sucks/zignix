const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @import("./c.zig");
const libnix = c.libnix;
const errors = @import("./error.zig");
const NixError = errors.NixError;
const nixError = errors.nixError;
const expr = @import("./expr.zig");
const EvalState = expr.EvalState;
const Value = expr.Value;
const util = @import("./util.zig");
const NixContext = util.NixContext;

/// A settings object for configuring behavior related to Nix flakes.
pub const FlakeSettings = struct {
    settings: *libnix.nix_flake_settings,

    const Self = @This();

    /// Create a new instance of a Nix flake settings collection.
    ///
    /// Remember to release resources using `deinit()`.
    pub fn init(context: *NixContext) !Self {
        const flake_settings = libnix.nix_flake_settings_new(context.context) orelse return Allocator.Error.OutOfMemory;

        return Self{
            .settings = flake_settings,
        };
    }

    /// Release the resources associated with this settings object.
    ///
    /// Does not fail.
    pub fn deinit(self: Self) void {
        libnix.nix_flake_settings_free(self.settings);
    }
};

/// Settings that control the parsing of Nix flake references.
pub const FlakeRefParseFlags = struct {
    flags: *libnix.nix_flake_reference_parse_flags,
    flake_settings: *FlakeSettings,
    fetchers_settings: *libnix.nix_fetchers_settings,
    state: EvalState,
    allocator: Allocator,

    const Self = @This();

    /// Create a new set of Nix flake parse flag settings,
    /// initialized to default settings.
    ///
    /// Remember to release resources using `deinit()`.
    pub fn init(allocator: Allocator, context: *NixContext, settings: *FlakeSettings, state: EvalState) !Self {
        const flags = libnix.nix_flake_reference_parse_flags_new(context.context, settings.settings) orelse return Allocator.Error.OutOfMemory;
        errdefer libnix.nix_flake_reference_parse_flags_free(flags);

        const fetchers_settings = libnix.nix_fetchers_settings_new(context.context) orelse return Allocator.Error.OutOfMemory;

        return Self{
            .flags = flags,
            .flake_settings = settings,
            .fetchers_settings = fetchers_settings,
            .state = state,
            .allocator = allocator,
        };
    }

    /// Provide a base directory for parsing relative flake references.
    pub fn setBaseDirectory(self: Self, context: *NixContext, dir: []const u8) !void {
        const dirZ = self.allocator.dupeZ(u8, dir);
        defer self.allocator.free(dirZ);

        const err = libnix.nix_flake_reference_parse_flags_set_base_directory(context.context, self.flags, dirZ.ptr, dir.len);
        if (err != 0) return nixError(err);
    }

    /// Release the resources associated with this settings object.
    ///
    /// Does not fail.
    pub fn deinit(self: Self) void {
        libnix.nix_fetchers_settings_free(self.fetchers_settings);
        libnix.nix_flake_reference_parse_flags_free(self.flags);
    }
};

/// Settings that control what to do with the Nix flake lockfile.
pub const FlakeLockFlags = struct {
    flags: *libnix.nix_flake_lock_flags,
    flake_settings: *FlakeSettings,
    fetchers_settings: *libnix.nix_fetchers_settings,
    state: EvalState,
    allocator: Allocator,

    const Self = @This();

    /// Create a new set of Nix flake lock settings,
    /// initialized to default settings.
    ///
    /// Remember to release resources using `deinit()`.
    pub fn init(allocator: Allocator, context: *NixContext, settings: *FlakeSettings, state: EvalState) !Self {
        const flags = libnix.nix_flake_lock_flags_new(context.context, settings.settings) orelse return Allocator.Error.OutOfMemory;
        errdefer libnix.nix_flake_lock_flags_free(flags);

        const fetchers_settings = libnix.nix_fetchers_settings_new(context.context) orelse return Allocator.Error.OutOfMemory;

        return Self{
            .flags = flags,
            .flake_settings = settings,
            .fetchers_settings = fetchers_settings,
            .state = state,
            .allocator = allocator,
        };
    }

    /// Put the lock flags in a mode that checks whether the lock is up to date.
    pub fn setCheckMode(self: Self) void {
        _ = libnix.nix_flake_lock_flags_set_mode_check(null, self.flags);
    }

    /// Put the lock flags in a mode that updates the lock file in memory, if needed.
    pub fn setVirtualMode(self: Self) void {
        _ = libnix.nix_flake_lock_flags_set_mode_virtual(null, self.flags);
    }

    /// Put the lock flags in a mode that updates the lock file on disk, if needed.
    pub fn setWriteAsNeededMode(self: Self) void {
        _ = libnix.nix_flake_lock_flags_set_mode_write_as_needed(null, self.flags);
    }

    /// Override an existing input in the flake input set.
    ///
    /// This must use another initialized FlakeReference.
    pub fn overrideInput(self: Self, context: *NixContext, name: []const u8, ref: FlakeReference) !void {
        const nameZ = self.allocator.dupeZ(u8, name);
        defer self.allocator.free(nameZ);

        const err = libnix.nix_flake_lock_flags_add_input_override(context.context, self.flags, nameZ.ptr, ref.ref);
        if (err != 0) return nixError(err);
    }

    pub fn deinit(self: Self) void {
        libnix.nix_fetchers_settings_free(self.fetchers_settings);
        libnix.nix_flake_lock_flags_free(self.flags);
    }
};

/// A reference to a flake in memory.
///
/// This may contain a "fragment", which indicates a path
/// to a value of the flake's output attribute set.
pub const FlakeReference = struct {
    ref: *libnix.nix_flake_reference,
    fragment: []const u8,
    flags: *FlakeRefParseFlags,
    state: EvalState,
    allocator: Allocator,

    const Self = @This();

    /// Obtain a flake reference from a URL-like string.
    ///
    /// This URL may optionally contain a fragment, which is a path
    /// to a specific value inside of the flake's output attribute set.
    /// This is stored inside of the returned fragment field.
    ///
    /// Caller must call `deinit()` to release all memory, and does not
    /// own the `fragment` field's memory.
    pub fn fromSlice(allocator: Allocator, context: *NixContext, slice: []const u8, flags: *FlakeRefParseFlags) !Self {
        const sliceZ = try allocator.dupeZ(u8, slice);
        defer allocator.free(sliceZ);

        var fragment_data = c.StringDataContainer.new(allocator);

        var ref: ?*libnix.nix_flake_reference = null;

        const err = libnix.nix_flake_reference_and_fragment_from_string(
            context.context,
            flags.fetchers_settings,
            flags.flake_settings.settings,
            flags.flags,
            sliceZ.ptr,
            slice.len,
            &ref,
            c.genericGetStringCallback,
            &fragment_data,
        );
        if (err != 0) return nixError(err);

        const fragment = fragment_data.result orelse return Allocator.Error.OutOfMemory;

        return Self{
            .ref = ref.?,
            .flags = flags,
            .fragment = fragment,
            .state = flags.state,
            .allocator = allocator,
        };
    }

    /// Lock a flake, if it is not already locked.
    ///
    /// This is required to obtain the flake output attribute set.
    ///
    /// Remember to call `deinit()` on the returned value to release
    /// the locked flake's resources.
    pub fn lock(self: Self, context: *NixContext, flags: *FlakeLockFlags) !LockedFlake {
        const locked_flake = libnix.nix_flake_lock(
            context.context,
            self.flags.fetchers_settings,
            self.flags.flake_settings.settings,
            self.state.state,
            flags.flags,
            self.ref,
        ) orelse {
            try context.errorCode();
            unreachable;
        };

        return LockedFlake{
            .flake = locked_flake,
            .flake_settings = self.flags.flake_settings.settings,
            .state = self.flags.state,
            .allocator = self.allocator,
        };
    }

    /// Release all the resources associated with this flake reference.
    ///
    /// Does not fail.
    pub fn deinit(self: Self) void {
        self.allocator.free(self.fragment);
        libnix.nix_flake_reference_free(self.ref);
    }
};

/// A flake that has a suitable lock. Locked flakes are the only kind of
/// flake that allow access to outputs.
///
/// This lock could be a file on disk, or in-memory only, depending on the
/// lock mode configured in the flags.
pub const LockedFlake = struct {
    flake: *libnix.nix_locked_flake,
    flake_settings: *libnix.nix_flake_settings,
    state: EvalState,
    allocator: Allocator,

    const Self = @This();

    /// Get the output attribute set for a flake.
    ///
    /// This is guaranteed to be an value of type `attrset` if
    /// it does not fail.
    pub fn outputAttrs(self: Self, context: *NixContext) !Value {
        const value = libnix.nix_locked_flake_get_output_attrs(
            context.context,
            self.flake_settings,
            self.state.state,
            self.flake,
        ) orelse {
            try context.errorCode();
            unreachable;
        };

        return Value{
            .value = value,
            .state = self.state,
            .allocator = self.allocator,
        };
    }

    /// Release the resources associated with a nix_locked_flake.
    ///
    /// Does not fail.
    pub fn deinit(self: Self) void {
        libnix.nix_locked_flake_free(self.flake);
    }
};

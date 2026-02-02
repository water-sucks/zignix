const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const util = @import("./util.zig");
const NixContext = util.NixContext;

const errors = @import("./error.zig");
const nixError = errors.nixError;
const NixError = errors.NixError;

const c = @import("./c.zig");
const libnix = c.libnix;

/// Initialize the Nix store library. Call this before
/// creating a store; it can be called multiple times.
pub fn init(context: *NixContext, load_config: bool) NixError!void {
    const err = if (load_config)
        libnix.nix_libstore_init(context.context)
    else
        libnix.nix_libstore_init_no_load_config(context.context);

    if (err != 0) return nixError(err);
}

/// Load plugins specified in the settings. Call this
/// once, after calling the other init functions and setting
/// any desired settings.
pub fn initPlugins(context: *NixContext) NixError!void {
    const err = libnix.nix_init_plugins(context.context);
    if (err != 0) return nixError(err);
}

pub const Store = struct {
    store: *libnix.Store,
    allocator: Allocator,

    const Self = @This();

    /// Open a Nix store. Call `deinit()` after to release memory.
    pub fn open(allocator: Allocator, context: *NixContext, uri: []const u8, options: anytype) !Self {
        _ = options;

        const uriZ = try allocator.dupeZ(u8, uri);
        defer allocator.free(uriZ);

        const new_store = libnix.nix_store_open(context.context, uriZ.ptr, null);
        if (new_store == null) {
            try context.errorCode(); // See if there was a Nix error first.
            return error.OutOfMemory; // Otherwise, probably out of memory.
        }

        return Self{
            .store = new_store.?,
            .allocator = allocator,
        };
    }

    /// Get the version of a Nix store.
    ///
    /// Caller owns returned memory.
    pub fn getVersion(self: Self, context: *NixContext) ![]u8 {
        var string_data = c.StringDataContainer.new(self.allocator);

        const err = libnix.nix_store_get_version(context.context, self.store, c.genericGetStringCallback, &string_data);
        if (err != 0) return nixError(err);

        return string_data.result orelse Allocator.Error.OutOfMemory;
    }

    /// Get the URI of a Nix store.
    ///
    /// Caller owns returned memory.
    pub fn getUri(self: Self, context: *NixContext) ![]u8 {
        var string_data = c.StringDataContainer.new(self.allocator);

        const err = libnix.nix_store_get_uri(context.context, self.store, c.genericGetStringCallback, &string_data);
        if (err != 0) return nixError(err);

        return string_data.result orelse Allocator.Error.OutOfMemory;
    }

    /// Get the store directory of a Nix store.
    ///
    /// Caller owns returned memory.
    pub fn getStoreDir(self: Self, context: *NixContext) ![]u8 {
        var string_data = c.StringDataContainer.new(self.allocator);

        const err = libnix.nix_store_get_storedir(context.context, self.store, c.genericGetStringCallback, &string_data);
        if (err != 0) return nixError(err);

        return string_data.result orelse Allocator.Error.OutOfMemory;
    }

    /// Retrieve a store path from a Nix store.
    pub fn parsePath(self: Self, context: *NixContext, path: []const u8) !StorePath {
        const pathZ = try self.allocator.dupeZ(u8, path);
        defer self.allocator.free(pathZ);

        const store_path = libnix.nix_store_parse_path(context.context, self.store, pathZ);
        if (store_path == null) {
            try context.errorCode(); // See if there was a Nix error first.
            return error.OutOfMemory; // Otherwise, probably out of memory.
        }

        return StorePath{
            .path = store_path.?,
            .store = self,
            .allocator = self.allocator,
        };
    }

    pub fn copyClosure(self: Self, context: *NixContext, dest: Store, path: StorePath) !void {
        if (self.store != path.store.store) {
            @panic("passed StorePath did not come from this store");
        }

        const err = libnix.nix_store_copy_closure(context.context, self.store, dest.store, path.path);
        if (err != 0) return nixError(err);
    }

    /// Deallocate this Nix store. Does not fail.
    pub fn deinit(self: Self) void {
        libnix.nix_store_free(self.store);
    }
};

pub const RealisedPath = struct {
    name: []const u8,
    out_path: []const u8,
    allocator: Allocator,

    const Self = @This();

    pub fn deinit(self: Self) void {
        self.allocator.free(self.name);
        self.allocator.free(self.out_path);
    }
};

pub const StorePath = struct {
    path: *libnix.StorePath,
    store: Store,
    allocator: Allocator,

    const Self = @This();

    // Get the path name (e.g. "name" in /nix/store/...-name).
    //
    // Caller owns returned memory.
    pub fn name(self: Self) ![]const u8 {
        var string_data = c.StringDataContainer.new(self.allocator);

        const err = libnix.nix_store_path_name(self.path, c.genericGetStringCallback, &string_data);
        if (err != 0) return nixError(err);

        return string_data.result orelse Allocator.Error.OutOfMemory;
    }

    /// Get the physical location of a store path.
    ///
    /// Not all stores support this operation.
    ///
    /// Caller owns returned memory.
    pub fn realPath(self: Self, context: *NixContext) ![]const u8 {
        var string_data = c.StringDataContainer.new(self.allocator);

        const err = libnix.nix_store_real_path(context.context, self.store.store, self.path, c.genericGetStringCallback, &string_data);
        if (err != 0) return nixError(err);

        return string_data.result orelse Allocator.Error.OutOfMemory;
    }

    /// Check if this StorePath is valid (aka if exists in the referenced
    /// store). Error info is stored in the passed context.
    pub fn isValid(self: Self, context: *NixContext) bool {
        const valid = libnix.nix_store_is_valid_path(context.context, self.store, self.path);
        return valid;
    }

    // Copy a StorePath value.
    //
    // Caller owns returned memory and must call `deinit()`
    // to release held memory.
    pub fn clone(self: Self) !Self {
        const cloned_value = libnix.nix_store_path_clone(self.path);
        return Self{
            .path = cloned_value,
            .store = self.store,
            .allocator = self.allocator,
        };
    }

    export fn realiseCallback(user_data: ?*anyopaque, out_name: [*c]const u8, out: [*c]const u8) callconv(.c) void {
        const data: *StorePath.RealisedPathContainer = @ptrCast(@alignCast(user_data.?));

        data.name = data.allocator.dupe(u8, mem.sliceTo(mem.span(out_name), 0)) catch null;
        data.out_path = data.allocator.dupe(u8, mem.sliceTo(mem.span(out), 0)) catch null;
    }

    const RealisedPathContainer = struct {
        name: ?[]const u8,
        out_path: ?[]const u8,
        allocator: Allocator,

        pub fn deinit(self: @This()) void {
            if (self.out_path) |path| {
                self.allocator.free(path);
            }

            if (self.name) |n| {
                self.allocator.free(n);
            }
        }
    };

    /// Realise a Nix store path. This is a blocking function.
    ///
    /// Caller must call deinit() on the returned realised path to
    /// release memory.
    pub fn realise(
        self: Self,
        context: *NixContext,
    ) NixError!RealisedPath {
        var container = StorePath.RealisedPathContainer{
            .name = null,
            .out_path = null,
            .allocator = self.allocator,
        };
        errdefer container.deinit();

        const err = libnix.nix_store_realise(context.context, self.store.store, self.path, &container, StorePath.realiseCallback);
        if (err != 0) return nixError(err);

        return RealisedPath{
            .name = container.name.?,
            .out_path = container.out_path.?,
            .allocator = container.allocator,
        };
    }

    // Deallocate this StorePath. Does not fail.
    pub fn deinit(self: Self) void {
        libnix.nix_store_path_free(self.path);
    }
};

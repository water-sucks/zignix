const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.array_list.Managed;

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

/// Reference to a Nix store instance.
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

    /// Copy the closure of path from from this store
    /// to the provided destination store.
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

/// A realised path output.
///
/// Call `.deinit()` to release resources.
pub const RealisedPath = struct {
    /// Name of the realised path
    name: []const u8,
    /// Store path instance for the output
    out: StorePath,
    allocator: Allocator,

    const Self = @This();

    pub fn deinit(self: Self) void {
        self.allocator.free(self.name);
        self.out.deinit();
    }
};

/// A store path instance associated with a particular Nix store.
///
/// Call `.deinit()` to release resources.
pub const StorePath = struct {
    path: *libnix.StorePath,
    store: Store,
    allocator: Allocator,

    const Self = @This();

    /// Get the path name (e.g. "name" in /nix/store/...-name).
    ///
    /// Caller owns returned memory.
    pub fn name(self: Self) ![]const u8 {
        var string_data = c.StringDataContainer.new(self.allocator);

        libnix.nix_store_path_name(self.path, c.genericGetStringCallback, &string_data);

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

    /// Copy a StorePath value and create a new instance.
    ///
    /// Caller owns returned memory and must call `deinit()`
    /// to release held memory.
    pub fn clone(self: Self) !Self {
        const cloned_value = libnix.nix_store_path_clone(self.path);
        return Self{
            .path = cloned_value,
            .store = self.store,
            .allocator = self.allocator,
        };
    }

    /// Retrieve the derivation associated with the store path.
    ///
    /// Caller must call `.deinit()` to release owned memory.
    pub fn getDrv(self: Self, context: NixContext) !Derivation {
        const drv = libnix.nix_store_drv_from_store_path(context.context, self.store.store, self.path) orelse return error.OutOfMemory;

        return Derivation{
            .store = self.store,
            .drv = drv,
        };
    }

    /// Optional parameters for the getFSClosure() function.
    const FSClosureOptions = struct {
        /// The direction of closures to compute.
        ///
        /// The forward closure is paths referenced by any store
        /// path in the closure, while the backward closure is
        /// paths that reference any store path in the closure.
        direction: enum { forward, backward } = .forward,

        /// If computing the forward closure: for any derivation
        /// in the closure, include its outputs.
        ///
        /// If computing the backward closure: for any output in
        /// the closure, include derivations that produce it.
        include_outputs: bool = false,

        /// If computing the forward closure: for any output in the
        /// closure, include the derivation that produced it.
        ///
        /// If computing the backward closure: for any derivation in the
        /// closure, include its outputs.
        include_derivers: bool = false,
    };

    /// Create an iterator over the closure of a specific store path.
    ///
    /// Caller owns returned memory, and must call `deinit()` to release
    /// the resources associated with the iterator.
    ///
    /// FIXME: this currently loads all store paths into memory, and
    /// doesn't do true lazy iteration. When Nix releases a streaming
    /// variant of iterating the closure paths, this function should
    /// be updated accordingly.
    pub fn getFSClosure(self: Self, context: *NixContext, options: FSClosureOptions) !ClosureIterator {
        const flip_direction = switch (options.direction) {
            .forward => false,
            .backward => true,
        };

        var paths: ArrayList(StorePath) = .init(self.allocator);
        errdefer {
            for (paths.items) |path| {
                path.deinit();
            }
            paths.deinit();
        }

        var container = FSClosureCallbackContainer{
            .paths = &paths,
            .store = self.store,
            .allocator = self.allocator,
        };

        const err = libnix.nix_store_get_fs_closure(context.context, self.store.store, self.path, flip_direction, options.include_outputs, options.include_derivers, &container, fsClosureCallback);
        if (err != 0) return nixError(err);

        return ClosureIterator{
            .allocator = self.allocator,
            .paths = try paths.toOwnedSlice(),
        };
    }

    export fn fsClosureCallback(context: ?*libnix.nix_c_context, user_data: ?*anyopaque, store_path: ?*const libnix.StorePath) callconv(.c) void {
        _ = context;

        const data: *FSClosureCallbackContainer = @ptrCast(@alignCast(user_data.?));

        const path_to_add = libnix.nix_store_path_clone(store_path);
        if (path_to_add) |path| {
            data.paths.append(StorePath{
                .allocator = data.allocator,
                .store = data.store,
                .path = path,
            }) catch {};
        }
    }

    const FSClosureCallbackContainer = struct {
        allocator: Allocator,
        store: Store,
        paths: *ArrayList(StorePath),
    };

    export fn realiseCallback(user_data: ?*anyopaque, out_name: [*c]const u8, out: ?*const libnix.StorePath) callconv(.c) void {
        const data: *RealisedPathContainer = @ptrCast(@alignCast(user_data.?));

        data.name = data.allocator.dupe(u8, mem.sliceTo(mem.span(out_name), 0)) catch null;
        data.out_path = out;
    }

    const RealisedPathContainer = struct {
        name: ?[]const u8,
        out_path: ?*const libnix.StorePath,
        allocator: Allocator,

        pub fn deinit(self: @This()) void {
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
    ) !RealisedPath {
        var container = RealisedPathContainer{
            .name = null,
            .out_path = null,
            .allocator = self.allocator,
        };
        errdefer container.deinit();

        const err = libnix.nix_store_realise(context.context, self.store.store, self.path, &container, realiseCallback);
        if (err != 0) return nixError(err);

        const cloned_path = libnix.nix_store_path_clone(container.out_path.?) orelse return error.OutOfMemory;

        return RealisedPath{
            .name = container.name.?,
            .out = StorePath{
                .allocator = self.allocator,
                .store = self.store,
                .path = cloned_path,
            },
            .allocator = container.allocator,
        };
    }

    // Deallocate this StorePath. Does not fail.
    pub fn deinit(self: Self) void {
        libnix.nix_store_path_free(self.path);
    }
};

/// An instantiation of a Nix derivation.
pub const Derivation = struct {
    drv: *libnix.nix_derivation,
    allocator: Allocator,

    const Self = @This();

    /// Create a Nix derivation from a JSON-formatted representation
    /// of that derivation.
    ///
    /// Unlike toJSON(), this needs a Store. This is because over time,
    /// we expect the internal representation of derivations in Nix to
    /// differ from accepted derivation formats.
    ///
    /// The store argument is here to help any logic needed to convert
    /// from JSON to the internal representation, in excess of just parsing.
    pub fn fromJSON(allocator: Allocator, context: *NixContext, store: *Store, input: []const u8) !Self {
        const inputZ = try allocator.dupeZ(u8, input);
        defer allocator.free(inputZ);

        const drv = libnix.nix_derivation_from_json(context.context, store.store, inputZ.ptr) orelse {
            try context.errorCode();
            return Allocator.Error.OutOfMemory;
        };

        return Self{
            .drv = drv,
            .allocator = allocator,
        };
    }

    /// Add the given derivation to the provided Nix store.
    ///
    /// Returns the added store path, or an error on failure.
    pub fn addToStore(self: Self, context: *NixContext, store: *Store) !StorePath {
        const path = libnix.nix_add_derivation(context.context, store.store, self.drv) orelse {
            try context.errorCode();
            return Allocator.Error.OutOfMemory;
        };

        return StorePath{
            .allocator = self.allocator,
            .path = path,
            .store = store.*,
        };
    }

    /// Serialize this derivation as a JSON-formatted representation.
    ///
    /// Caller owns returned memory.
    pub fn toJSON(self: Self, context: *NixContext) ![]const u8 {
        var string_data = c.StringDataContainer.new(self.allocator);

        const err = libnix.nix_derivation_to_json(context.context, self.path, c.genericGetStringCallback, &string_data);
        if (err != 0) return nixError(err);

        return string_data.result orelse Allocator.Error.OutOfMemory;
    }

    /// Deallocate this derivation. Does not fail.
    pub fn deinit(self: Self) void {
        libnix.nix_derivation_free(self.drv);
    }
};

/// A Nix closure iterator.
///
/// NOTE: In the future, if Nix exposes a streaming API for getting the
/// closure for a particular store path, then this will use that,
/// but currently the paths are all fetched eagerly, and this is
/// an iterator over those already-computed store paths.
const ClosureIterator = struct {
    allocator: Allocator,
    paths: []StorePath,
    index: usize = 0,

    /// Move to the next path in the closure, if it exists.
    ///
    /// If no more paths are needed, then null is returned.
    ///
    /// Do NOT call `deinit()` on these store paths; this will
    /// be handled by the `ClosureIterator.deinit()` method.
    pub fn next(self: *ClosureIterator) ?StorePath {
        if (self.index >= self.paths.len) {
            return null;
        }
        defer self.index += 1;
        return self.paths[self.index];
    }

    /// Deallocate this ClosureIterator and all store paths
    /// associated with it. Does not fail.
    pub fn deinit(self: *ClosureIterator) void {
        for (self.paths) |path| {
            path.deinit();
        }
        self.allocator.free(self.paths);
    }
};

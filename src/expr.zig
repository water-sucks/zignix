const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const errors = @import("./error.zig");
const nixError = errors.nixError;
const NixError = errors.NixError;

const util = @import("./util.zig");
const NixContext = util.NixContext;

const lstore = @import("./store.zig");
const Store = lstore.Store;

const libnix = @import("./c.zig").libnix;

/// Initialize the Nix expression evaluator. Call this function
/// before creating any `State`s; it can be called multiple times.
pub fn init(context: NixContext) NixError!void {
    const err = libnix.nix_libexpr_init(context.context);
    if (err != 0) return nixError(err);
}

pub const EvalState = struct {
    state: *libnix.EvalState,
    store: *libnix.Store,

    const Self = @This();

    /// Create a new Nix state. Caller must call `deinit()` to
    /// release memory.
    // TODO: add search path param
    pub fn init(context: NixContext, store: Store) !Self {
        var new_state = libnix.nix_state_create(context.context, null, store.store);
        if (new_state == null) {
            try context.errorCode();
            return error.OutOfMemory;
        }

        return Self{
            .state = new_state.?,
            .store = store.store,
        };
    }

    /// Allocate a Nix value. Owned by the GC; use
    /// `gc.deref` when finished with this value.
    pub fn createValue(self: Self, context: NixContext) !Value {
        var new_value = libnix.nix_alloc_value(context.context, self.state);
        if (new_value == null) {
            try context.errorCode();
            return error.OutOfMemory;
        }

        return Value{
            .value = new_value.?,
            .state = self.state,
        };
    }

    /// Parse and evaluates a Nix expression from a string.
    pub fn evalFromString(self: Self, allocator: Allocator, context: NixContext, expr: []const u8, path: []const u8, value: Value) !void {
        const exprZ = try allocator.dupeZ(u8, expr);
        defer allocator.free(exprZ);

        const pathZ = try allocator.dupeZ(u8, path);
        defer allocator.free(pathZ);

        const err = libnix.nix_expr_eval_from_string(context.context, self.state, expr.ptr, path.ptr, value.value);
        if (err != 0) return nixError(err);
    }

    /// Free this `NixState`. Does not fail.
    pub fn deinit(self: Self) void {
        libnix.nix_state_free(self.state);
    }
};

pub const ValueType = enum(u8) {
    thunk,
    int,
    float,
    bool,
    string,
    path,
    null,
    attrs,
    list,
    function,
    external,
};

// TODO: find out why asserts are segfaulting instead of returning error info?
pub const Value = struct {
    value: *libnix.Value,
    state: *libnix.EvalState,

    const Self = @This();

    /// Get a 64-bit integer value.
    pub fn int(self: Self, context: NixContext) !i64 {
        const result = libnix.nix_get_int(context.context, self.value);
        try context.errorCode();
        return result;
    }

    pub fn setInt(self: Self, context: NixContext, value: i64) !void {
        const err = libnix.nix_init_int(context.context, self.value, value);
        if (err != 0) return nixError(err);
    }

    /// Get a 64-bit floating-point value.
    pub fn float(self: Self, context: NixContext) !f64 {
        const result = libnix.nix_init_float(context.context, self.value);
        try context.errorCode();
        return result;
    }

    pub fn setFloat(self: Self, context: NixContext, value: f64) !void {
        const err = libnix.nix_init_float(context.context, self.value, value);
        if (err != 0) return nixError(err);
    }

    /// Get a boolean value.
    pub fn boolean(self: Self, context: NixContext) !bool {
        const result = libnix.nix_get_bool(context.context, self.value);
        try context.errorCode();
        return result;
    }

    pub fn setBoolean(self: Self, context: NixContext, value: bool) !void {
        const err = libnix.nix_init_bool(context.context, self.value, value);
        if (err != 0) return nixError(err);
    }

    /// Get a string value. Caller owns returned memory.
    pub fn string(self: Self, allocator: Allocator, context: NixContext) ![]const u8 {
        const result = libnix.nix_get_string(context.context, self.value);
        if (result) |value| {
            return allocator.dupe(u8, mem.sliceTo(value, 0));
        }
        try context.errorCode();
        unreachable;
    }

    pub fn setString(self: Self, context: NixContext, value: [:0]const u8) !void {
        const err = libnix.nix_init_string(context.context, self.value, value);
        if (err != 0) return nixError(err);
    }

    /// Get a path value as a string. Caller owns returned memory.
    pub fn pathString(self: Self, allocator: Allocator, context: NixContext) ![]const u8 {
        const result = libnix.nix_get_path_string(context.context, self.value);
        if (result) |value| {
            return allocator.dupe(u8, mem.sliceTo(value, 0));
        }
        try context.errorCode();
        unreachable;
    }

    pub fn setPath(self: Self, context: NixContext, value: [:0]const u8) !void {
        // FIXME: setting a path hangs for some reason.
        const err = libnix.nix_init_path_string(context.context, self.value, value);
        if (err != 0) return nixError(err);
    }

    pub fn setNull(self: Self, context: NixContext) !void {
        const err = libnix.nix_init_null(context.context, self.value);
        if (err != 0) return nixError(err);
    }

    /// Get the length of a list.
    pub fn listSize(self: Self, context: NixContext) !usize {
        const result = libnix.nix_get_list_size(context.context, self.value);
        try context.errorCode();
        return result;
    }

    /// Get the element of a list at index `i`. Clean this up
    /// using `gc.decref`.
    pub fn listAtIndex(self: Self, context: NixContext, i: usize) !Value {
        const result = libnix.nix_get_list_byidx(context.context, self.value, self.state, @intCast(i));
        if (result) |value| {
            return Value{
                .value = value,
                .state = self.state,
            };
        }
        try context.errorCode();
        unreachable;
    }

    /// Get the type of this value.
    pub fn valueType(self: Self) ValueType {
        const result = libnix.nix_get_type(null, self.value);
        return @enumFromInt(result);
    }

    /// Get the type name of this value as defined in the evaluator.
    /// Caller owns returned memory.
    pub fn typeName(self: Self, context: NixContext) ![]const u8 {
        const result = libnix.nix_get_typename(context.context, self.value);
        try context.errorCode();
        return mem.sliceTo(result, 0);
    }

    /// Copy the value from another value into this value.
    pub fn copy(self: Self, context: NixContext, src: Value) !void {
        const err = libnix.nix_copy_value(context.context, self.value, src.value);
        if (err != 0) return nixError(err);
    }

    // TODO: make a toOwnedSlice method for stringifying a value.
};

pub const gc = struct {
    /// Trigger the garbage collector manually.
    /// Useful for debugging.
    pub fn trigger() void {
        libnix.nix_gc_now();
    }

    /// Increment the garbage collector reference counter for the given object
    pub fn incRef(comptime T: type, context: NixContext, object: T) NixError!void {
        if (T == Value) {
            const err = libnix.nix_gc_incref(context.context, object.value);
            if (err != 0) return nixError(err);
        }

        // TODO: are there any more value types to handle?
        @compileError("value to increment GC refcount on must be a valid GC-able type");
    }

    /// Decrement the garbage collector reference counter for the given object.
    pub fn decRef(comptime T: type, context: NixContext, object: T) NixError!void {
        if (T == Value) {
            const err = libnix.nix_gc_decref(context.context, object.value);
            if (err != 0) return nixError(err);
        } else {
            // TODO: are there any more value types to handle?
            @compileError("value to increment GC refcount on must be a valid GC-able type");
        }
    }
};

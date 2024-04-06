const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const testing = std.testing;
const Allocator = mem.Allocator;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualSlices = testing.expectEqualSlices;

const errors = @import("./error.zig");
const nixError = errors.nixError;
const NixError = errors.NixError;

const util = @import("./util.zig");
const NixContext = util.NixContext;

const lstore = @import("./store.zig");
const Store = lstore.Store;

const libnix = @import("./c.zig").libnix;

const TestUtils = @import("testing.zig").TestUtils;

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

    const AttrKeyValue = struct {
        name: []const u8,
        value: Value,
    };

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
        const result = libnix.nix_get_float(context.context, self.value);
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

    /// Get a string value. Caller does not own returned memory.
    pub fn string(self: Self, context: NixContext) ![]const u8 {
        const result = libnix.nix_get_string(context.context, self.value);
        if (result) |value| {
            return mem.sliceTo(mem.span(value), 0);
        }
        try context.errorCode();
        unreachable;
    }

    pub fn setString(self: Self, context: NixContext, value: [:0]const u8) !void {
        const err = libnix.nix_init_string(context.context, self.value, value);
        if (err != 0) return nixError(err);
    }

    /// Get a path value as a string. Caller does not own returned memory.
    pub fn pathString(self: Self, context: NixContext) ![]const u8 {
        const result = libnix.nix_get_path_string(context.context, self.value);
        if (result) |value| {
            return mem.sliceTo(mem.span(value), 0);
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

    /// Set a list value from a list builder.
    pub fn setList(self: Self, context: NixContext, builder: ListBuilder) !void {
        const err = libnix.nix_make_list(context.context, builder.builder, self.value);
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

    /// Return a list iterator.
    pub fn listIterator(self: Self, context: NixContext) !ListIterator {
        const size = try self.listSize(context);

        return ListIterator{
            .list = self,
            .size = size,
        };
    }

    /// Set an attrset value from a attrset bindings builder.
    pub fn setAttrs(self: Self, context: NixContext, builder: BindingsBuilder) !void {
        const err = libnix.nix_make_attrs(context.context, self.value, builder.builder);
        if (err != 0) return nixError(err);
    }

    /// Retrieve the element count of an attrset.
    pub fn attrsetSize(self: Self, context: NixContext) !usize {
        const result = libnix.nix_get_attrs_size(context.context, self.value);
        try context.errorCode();
        return result;
    }

    /// Retrieve a key-value pair from the sorted bindings by index.
    /// Caller does not own `.name`, and must call `gc.decRef` on `.value`
    /// to release the created value.
    pub fn attrAtIndex(self: Self, context: NixContext, i: usize) !AttrKeyValue {
        var buf: [*c]u8 = undefined;
        const result = libnix.nix_get_attr_byidx(context.context, self.value, self.state, @intCast(i), &buf);
        if (result) |value| {
            return AttrKeyValue{
                .name = mem.sliceTo(mem.span(buf), 0),
                .value = Value{
                    .state = self.state,
                    .value = value,
                },
            };
        }

        try context.errorCode();
        unreachable;
    }

    /// Retrieve an attr value by name. Call `gc.decRef` to release the
    /// created value.
    pub fn attrByName(self: Self, context: NixContext, name: [:0]const u8) !Value {
        const result = libnix.nix_get_attr_byname(context.context, self.value, self.state, name);
        if (result) |value| {
            return Value{
                .state = self.state,
                .value = value,
            };
        }

        try context.errorCode();
        unreachable;
    }

    /// Retrieve an attr name by index in the sorted bindings. Avoids
    /// evaluation of the value; caller does not own returned memory.
    pub fn attrNameAtIndex(self: Self, context: NixContext, i: usize) ![]const u8 {
        const result = libnix.nix_get_attr_name_byidx(context.context, self.value, self.state, @intCast(i));
        if (result) |value| {
            return mem.sliceTo(mem.span(value), 0);
        }

        try context.errorCode();
        unreachable;
    }

    /// Check if an attr with the provided name exists in this attrset.
    pub fn hasAttrWithName(self: Self, context: NixContext, name: [:0]const u8) !bool {
        const exists = libnix.nix_has_attr_byname(context.context, self.value, self.state, name);
        try context.errorCode();
        return exists;
    }

    /// Get the type of this value.
    pub fn valueType(self: Self) ValueType {
        const result = libnix.nix_get_type(null, self.value);
        return @enumFromInt(result);
    }

    /// Get the type name of this value as defined in the evaluator.
    /// Caller does not own returned memory.
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

pub const ListBuilder = struct {
    state: *libnix.EvalState,
    builder: *libnix.ListBuilder,

    const Self = @This();

    pub fn init(context: NixContext, state: EvalState, capacity: usize) !Self {
        var builder = libnix.nix_make_list_builder(context.context, state.state, capacity);
        if (builder == null) {
            try context.errorCode();
            return error.OutOfMemory;
        }

        return Self{
            .state = state.state,
            .builder = builder.?,
        };
    }

    pub fn insert(self: Self, context: NixContext, index: c_uint, value: Value) NixError!void {
        const err = libnix.nix_list_builder_insert(context.context, self.builder, index, value.value);
        if (err != 0) return nixError(err);
    }

    pub fn deinit(self: Self) void {
        libnix.nix_list_builder_free(self.builder);
    }
};

pub const BindingsBuilder = struct {
    state: *libnix.EvalState,
    builder: *libnix.BindingsBuilder,

    const Self = @This();

    pub fn init(context: NixContext, state: EvalState, capacity: usize) !Self {
        var builder = libnix.nix_make_bindings_builder(context.context, state.state, capacity);
        if (builder == null) {
            try context.errorCode();
            return error.outOfMemory;
        }

        return Self{
            .state = state.state,
            .builder = builder.?,
        };
    }

    pub fn insert(self: Self, context: NixContext, name: [:0]const u8, value: Value) NixError!void {
        const err = libnix.nix_bindings_builder_insert(context.context, self.builder, name, value.value);
        if (err != 0) return nixError(err);
    }

    pub fn deinit(self: Self) void {
        libnix.nix_bindings_builder_free(self.builder);
    }
};

pub const ListIterator = struct {
    list: Value,
    size: usize,
    index: usize = 0,

    const Self = @This();

    /// Return the next element in the list as a `Value` if it exists.
    /// Clean this value up using `gc.decRef`.
    pub fn next(self: *Self, context: NixContext) !?Value {
        if (self.index == self.size) {
            return null;
        }

        const current_index = self.index;
        self.index += 1;

        return try self.list.listAtIndex(context, current_index);
    }
};

test "get/set integer" {
    const allocator = testing.allocator;
    const resources = try TestUtils.initResources(allocator);
    const context = resources.context;
    const state = resources.state;

    const value = try state.createValue(context);
    try value.setInt(context, 10);

    const actual = try value.int(context);
    const expected: i64 = 10;

    try expectEqual(expected, actual);
}

test "get/set float" {
    const allocator = testing.allocator;
    const resources = try TestUtils.initResources(allocator);
    const context = resources.context;
    const state = resources.state;

    const value = try state.createValue(context);
    try value.setFloat(context, 3.14);

    const actual = try value.float(context);
    const expected: f64 = 3.14;

    try expectEqual(expected, actual);
}

test "get/set bool" {
    const allocator = testing.allocator;
    const resources = try TestUtils.initResources(allocator);
    const context = resources.context;
    const state = resources.state;

    const value = try state.createValue(context);
    try value.setBoolean(context, false);

    const actual = try value.boolean(context);
    const expected: bool = false;

    try expectEqual(expected, actual);
}

test "get/set string slice" {
    const allocator = testing.allocator;
    const resources = try TestUtils.initResources(allocator);
    const context = resources.context;
    const state = resources.state;

    const value = try state.createValue(context);
    try value.setString(context, "Goodbye, cruel world!");

    const actual = try value.string(context);
    const expected: []const u8 = "Goodbye, cruel world!";

    try expectEqualSlices(u8, expected, actual);
}

// This test does not work, due to setting a path hanging.
// test "get/set path string slice" {
//     const allocator = testing.allocator;
//     const resources = try TestUtils.initResources(allocator);
//     const context = resources.context;
//     const state = resources.state;
//
//     const value = try state.createValue(context);
//     try value.setStringPath(context, "/nix/store");
//
//     const actual = try value.pathString(allocator, context);
//     const expected: []const u8 = "/nix/store";
//
//     try expectEqualSlices(u8, expected, actual);
// }

test "set null" {
    const allocator = testing.allocator;
    const resources = try TestUtils.initResources(allocator);
    const context = resources.context;
    const state = resources.state;

    const value = try state.createValue(context);
    try value.setString(context, "Goodbye, cruel world!");

    try value.setNull(context);
    try expect(value.valueType() == .null);
}

test "build/set list value" {
    const allocator = testing.allocator;
    const resources = try TestUtils.initResources(allocator);
    const context = resources.context;
    const state = resources.state;

    const value = try TestUtils.createList(context, state);

    try expect(value.valueType() == .list);
    const expected_size: usize = 10;
    try expectEqual(expected_size, try value.listSize(context));
}

test "iterate through list" {
    const allocator = testing.allocator;
    const resources = try TestUtils.initResources(allocator);
    const context = resources.context;
    const state = resources.state;

    const list_value = try TestUtils.createList(context, state);

    var expected_value: i64 = 0;
    var iter = try list_value.listIterator(context);
    while (try iter.next(context)) |value| {
        defer gc.decRef(Value, context, value) catch unreachable;
        const actual = try value.int(context);
        try expectEqual(expected_value, actual);
        expected_value += 1;
    }
}

test "set attrs" {
    const allocator = testing.allocator;
    const resources = try TestUtils.initResources(allocator);
    const context = resources.context;
    const state = resources.state;

    const value = try TestUtils.createAttrset(context, state);
    defer gc.decRef(Value, context, value) catch unreachable;

    try expect(value.valueType() == .attrs);
    const expected_size: usize = 3;
    try expectEqual(expected_size, try value.attrsetSize(context));
}

test "get attr at index" {
    const allocator = testing.allocator;
    const resources = try TestUtils.initResources(allocator);
    const context = resources.context;
    const state = resources.state;

    const value = try TestUtils.createAttrset(context, state);
    defer gc.decRef(Value, context, value) catch unreachable;

    const actual_kv = try value.attrAtIndex(context, 2);
    defer gc.decRef(Value, context, actual_kv.value) catch unreachable;

    try expectEqualSlices(u8, "what", actual_kv.name);
    try expectEqualSlices(u8, "a cruel world", try actual_kv.value.string(context));
}

test "get attr by name" {
    const allocator = testing.allocator;
    const resources = try TestUtils.initResources(allocator);
    const context = resources.context;
    const state = resources.state;

    const value = try TestUtils.createAttrset(context, state);
    defer gc.decRef(Value, context, value) catch unreachable;

    const retrieved_value = try value.attrByName(context, "goodbye");
    defer gc.decRef(Value, context, retrieved_value) catch unreachable;

    try expectEqualSlices(u8, "cruel world", try retrieved_value.string(context));
}

test "get attr name at index" {
    const allocator = testing.allocator;
    const resources = try TestUtils.initResources(allocator);
    const context = resources.context;
    const state = resources.state;

    const value = try TestUtils.createAttrset(context, state);
    defer gc.decRef(Value, context, value) catch unreachable;

    try expectEqualSlices(u8, "hello", try value.attrNameAtIndex(context, 0));
}

test "check if attrset has/does not have attrs" {
    const allocator = testing.allocator;
    const resources = try TestUtils.initResources(allocator);
    const context = resources.context;
    const state = resources.state;

    const value = try TestUtils.createAttrset(context, state);
    defer gc.decRef(Value, context, value) catch unreachable;

    try expect(try value.hasAttrWithName(context, "hello"));
    try expect(!try value.hasAttrWithName(context, "this attr does not exist"));
}

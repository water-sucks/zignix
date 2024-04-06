const std = @import("std");
const Allocator = std.mem.Allocator;

const nix = @import("../src/lib.zig");
const NixContext = nix.util.NixContext;
const Store = nix.store.Store;
const EvalState = nix.expr.EvalState;
const Value = nix.expr.Value;
const ListBuilder = nix.expr.ListBuilder;
const BindingsBuilder = nix.expr.BindingsBuilder;

pub const TestUtils = struct {
    pub const TestResources = struct {
        context: NixContext,
        store: Store,
        state: EvalState,
    };

    pub fn initResources(allocator: Allocator) !TestResources {
        const context = try NixContext.init();
        errdefer context.deinit();

        try nix.util.init(context);
        try nix.store.init(context);
        try nix.expr.init(context);

        const store = try Store.open(allocator, context, "", .{});
        errdefer store.deinit();

        const state = try EvalState.init(context, store);

        return TestResources{
            .context = context,
            .store = store,
            .state = state,
        };
    }

    pub fn createList(context: NixContext, state: EvalState) !Value {
        const value = try state.createValue(context);

        const builder = try ListBuilder.init(context, state, 10);
        defer builder.deinit();

        for (0..10) |i| {
            const lvalue = try state.createValue(context);
            try lvalue.setInt(context, @intCast(i));
            try builder.insert(context, @intCast(i), lvalue);
        }

        try value.setList(context, builder);
        return value;
    }

    pub fn createAttrset(context: NixContext, state: EvalState) !Value {
        const value = try state.createValue(context);
        const attrs = &.{
            .{ .name = "hello", .value = "world" },
            .{ .name = "goodbye", .value = "cruel world" },
            .{ .name = "what", .value = "a cruel world" },
        };

        const builder = try BindingsBuilder.init(context, state, 10);
        defer builder.deinit();

        inline for (attrs) |kv| {
            const attr_value = try state.createValue(context);
            try attr_value.setString(context, kv.value);
            try builder.insert(context, kv.name, attr_value);
        }

        try value.setAttrs(context, builder);
        return value;
    }
};

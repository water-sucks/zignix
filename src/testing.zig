const std = @import("std");
const Allocator = std.mem.Allocator;

const nix = @import("../src/lib.zig");
const NixContext = nix.util.NixContext;
const Store = nix.store.Store;
const EvalState = nix.expr.EvalState;

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
};

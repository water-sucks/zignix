const std = @import("std");
const print = std.debug.print;
const builtin = @import("builtin");

const zignix = @import("zignix");
const gc = zignix.expr.gc;

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const status = gpa.deinit();
        if (builtin.mode == .Debug) {
            print("memory leak status: {}\n", .{status});
        }
    }
    const allocator = gpa.allocator();

    const context = try zignix.NixContext.init(allocator);
    defer context.deinit();

    zignix.init(context) catch {
        const msg = context.errorMessage() catch "(failed to retrieve error message from context)";
        print("error: failed to initialize nix lib: {s}", .{msg.?});
        return 1;
    };

    try zignix.util.setVerbosity(context, .vomit);

    print("Evaluating a simple expression\n", .{});
    print("------------------------------\n", .{});

    const nix_store = zignix.NixStore.open(allocator, context, "", .{}) catch {
        const msg = context.errorMessage() catch "(failed to retrieve error message from context)";
        print("error: failed to open nix store: {s}\n", .{msg.?});
        return 1;
    };
    defer nix_store.deinit();

    const store_uri = try nix_store.getUri(context);
    defer allocator.free(store_uri);
    const store_dir = try nix_store.getStoreDir(context);
    defer allocator.free(store_dir);
    const store_version = try nix_store.getVersion(context);
    defer allocator.free(store_version);

    print("opened nix store :: url '{s}', dir '{s}' version '{s}'\n", .{ store_uri, store_dir, store_version });

    const eval_state = zignix.EvalState.init(allocator, context, nix_store) catch return 1;
    defer eval_state.deinit();

    const value = try eval_state.evalFromString(context, "1 + 1", ".");
    defer gc.decRef(zignix.NixValue, context, value) catch unreachable;

    print("1 + 1 = {d}\n", .{try value.int(context)});

    return 0;
}

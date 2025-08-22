const std = @import("std");
const print = std.debug.print;
const builtin = @import("builtin");

const zignix = @import("zignix");
const NixContext = zignix.NixContext;
const NixStore = zignix.store.Store;
const EvalState = zignix.expr.EvalState;
const gc = zignix.expr.gc;

const utils = @import("./utils.zig");

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const status = gpa.deinit();
        if (builtin.mode == .Debug) {
            print("memory leak status: {}\n", .{status});
        }
    }
    const allocator = gpa.allocator();

    const context = try NixContext.init(allocator);
    defer context.deinit();

    zignix.init(context) catch {
        const msg = context.errorMessage() catch "(failed to retrieve error message from context)";
        print("error: failed to initialize nix lib: {s}", .{msg.?});
        return 1;
    };

    const nix_store = NixStore.open(allocator, context, "", .{}) catch {
        const msg = context.errorMessage() catch "(failed to retrieve error message from context)";
        print("error: failed to open Nix store: {s}\n", .{msg.?});
        return 1;
    };
    defer nix_store.deinit();

    const eval_state = try utils.initEvalStateFromNixPath(allocator, context, nix_store);
    defer eval_state.deinit();

    print("Realising a single derivation using .drvPath\n", .{});
    print("--------------------------------------------\n", .{});

    const expr = "let pkgs = import <nixpkgs> {}; in pkgs.hello.drvPath";
    print("> {s}\n", .{expr});

    const drv_path_value = eval_state.evalFromString(context, expr, ".") catch {
        const msg = try context.errorInfoMessage();
        print("error: failed to evaluate value: {s}\n", .{msg});
        allocator.free(msg);

        try context.errorCode();
        unreachable;
    };

    const drv_path = drv_path_value.string(context) catch unreachable;
    defer allocator.free(drv_path);

    const path = nix_store.parsePath(context, drv_path) catch {
        const msg = context.errorMessage() catch "(failed to retrieve error message from context)";
        print("error: failed to parse nix store path: {s}\n", .{msg.?});

        try context.errorCode();
        unreachable;
    };
    defer path.deinit();

    const realised_path = path.realise(context) catch {
        const msg = context.errorMessage() catch "(failed to retrieve error message from context)";
        print("{s}\n", .{msg.?});

        try context.errorCode();
        unreachable;
    };
    defer realised_path.deinit();

    print("realized path :: {s} @ {s}\n", .{ realised_path.name, realised_path.out_path });

    return 0;
}

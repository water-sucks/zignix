const std = @import("std");
const print = std.debug.print;
const builtin = @import("builtin");

const zignix = @import("zignix");

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

    const context = try zignix.NixContext.init(allocator);
    defer context.deinit();

    try zignix.util.setVerbosity(context, .vomit);

    zignix.init(context) catch {
        const msg = context.errorMessage() catch "(failed to retrieve error message from context)";
        print("error: failed to initialize nix lib: {s}", .{msg.?});
        return 1;
    };

    const nix_store = zignix.NixStore.open(allocator, context, "", .{}) catch {
        const msg = context.errorMessage() catch "(failed to retrieve error message from context)";
        print("error: failed to open Nix store: {s}\n", .{msg.?});
        return 1;
    };
    defer nix_store.deinit();

    const eval_state = try utils.initEvalStateFromNixPath(allocator, context, nix_store);
    defer eval_state.deinit();

    print("Calculating the forward closure of a store path", .{});
    print("-----------------------------------------------\n", .{});

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

    var closure_iterator = try path.getFSClosure(context, .{
        .direction = .forward,
        .include_outputs = true,
        .include_derivers = true,
    });
    defer closure_iterator.deinit();

    while (closure_iterator.next()) |p| {
        const name = try p.name();
        defer allocator.free(name);

        print("{s}\n", .{name});
    }

    return 0;
}

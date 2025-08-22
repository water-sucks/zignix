const std = @import("std");
const print = std.debug.print;
const builtin = @import("builtin");

const zignix = @import("zignix");
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

    const context = try zignix.NixContext.init(allocator);
    defer context.deinit();

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

    print("Realising a string context\n", .{});
    print("--------------------------\n", .{});

    const expr =
        \\let
        \\  pkgs = import <nixpkgs> {};
        \\in ''
        \\  ${pkgs.hello}/bin/hello
        \\  ${pkgs.coreutils}/bin/ls
        \\''
    ;
    print("> {s}\n", .{expr});

    const value = eval_state.evalFromString(context, expr, ".") catch {
        const msg = try context.errorInfoMessage();
        print("error: failed to evaluate value: {s}\n", .{msg});
        allocator.free(msg);

        try context.errorCode();
        unreachable;
    };

    const realised = value.realiseString(context, false) catch {
        const msg = try context.errorInfoMessage();
        print("error: failed to evaluate value: {s}\n", .{msg});
        allocator.free(msg);

        try context.errorCode();
        unreachable;
    };
    defer realised.deinit();

    const realised_repr = try realised.asSlice();
    defer allocator.free(realised_repr);

    print("realised string repr :: {s}\n", .{realised_repr});

    print("iterating using store path iterator\n", .{});

    var store_path_iter = realised.iterator();
    while (try store_path_iter.next()) |path| {
        const real_path = path.realPath(context) catch unreachable;
        defer allocator.free(real_path);

        print("path :: {s}\n", .{real_path});
    }

    return 0;
}

const std = @import("std");
const mem = std.mem;
const posix = std.posix;
const Allocator = mem.Allocator;
const StringHashMap = std.StringHashMap;
const print = std.debug.print;
const builtin = @import("builtin");

const zignix = @import("zignix");
const NixContext = zignix.util.NixContext;
const NixStore = zignix.store.Store;
const EvalState = zignix.expr.EvalState;
const EvalStateBuilder = zignix.expr.EvalStateBuilder;

fn init_eval_state(allocator: Allocator, context: *NixContext, store: NixStore) !EvalState {
    const builder = EvalStateBuilder.init(allocator, context, store) catch |err| {
        print("error: failed to initialize nix eval state builder: {}\n", .{err});
        return err;
    };

    // As an example for how to use the builder, this parses the NIX_PATH.
    // However, in reality, this shouldn't be needed, as NIX_PATH is
    // automatically loaded by libnix itself.
    var lookup_paths = StringHashMap([]const u8).init(allocator);
    defer lookup_paths.deinit();

    const nix_path = posix.getenv("NIX_PATH") orelse "";
    var nix_path_entries = std.mem.tokenizeScalar(u8, nix_path, ':');

    while (nix_path_entries.next()) |part| {
        var lean = std.mem.tokenizeScalar(u8, part, '=');
        const key = lean.next() orelse return error.MalformedNixPath;
        const val = lean.next() orelse return error.MalformedNixPath;

        try lookup_paths.put(key, val);
    }

    builder.loadSettings(context) catch |err| {
        print("error: failed to load settings for nix eval state builder: {}\n", .{err});
        print("using default settings\n", .{});
    };

    builder.setLookupPath(context, lookup_paths) catch |err| {
        print("error: failed to initialize nix eval state builder: {}\n", .{err});
        return err;
    };

    const state = builder.build(context) catch |err| {
        print("error: failed to build nix eval state: {}\n", .{err});
        return err;
    };

    return state;
}

pub fn realise_using_drv_path(allocator: Allocator, context: *NixContext, state: EvalState, store: NixStore) !void {
    const drv_path_value = state.evalFromString(context, "let pkgs = import <nixpkgs> {}; in pkgs.hello.drvPath", ".") catch {
        const msg = try context.errorInfoMessage();
        print("error: failed to evaluate value: {s}\n", .{msg});
        allocator.free(msg);

        try context.errorCode();
        unreachable;
    };

    const drv_path = drv_path_value.string(context) catch unreachable;
    defer allocator.free(drv_path);

    const path = store.parsePath(context, drv_path) catch {
        const msg = context.errorMessage() catch @panic("unrecoverable error");
        print("error: failed to parse nix store path: {s}\n", .{msg.?});

        try context.errorCode();
        unreachable;
    };
    defer path.deinit();

    const realised_path = path.realise(context) catch {
        const msg = context.errorMessage() catch @panic("unrecoverable error");
        print("{s}\n", .{msg.?});

        try context.errorCode();
        unreachable;
    };
    defer realised_path.deinit();

    print("realized path :: {s} @ {s}\n", .{ realised_path.name, realised_path.out_path });
}

pub fn realise_using_string_context(allocator: Allocator, context: *NixContext, state: EvalState, store: NixStore) !void {
    _ = store;

    const expr_string =
        \\let
        \\  pkgs = import <nixpkgs> {};
        \\in ''
        \\  ${pkgs.hello}/bin/hello
        \\  ${pkgs.coreutils}/bin/ls
        \\''
    ;

    const value = state.evalFromString(context, expr_string, ".") catch {
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

    print("\n", .{});
}

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const status = gpa.deinit();
        if (builtin.mode == .Debug) {
            print("memory leak status: {}\n", .{status});
        }
    }
    const allocator = gpa.allocator();

    const version = zignix.util.version();
    std.debug.print("nix version :: {s}\n", .{version});

    const context = try NixContext.init(allocator);
    defer context.deinit();

    zignix.util.init(context) catch {
        const msg = context.errorMessage() catch @panic("unrecoverable error");
        print("error: failed to initialize nix utils lib: {s}", .{msg.?});
        return 1;
    };

    // A test of errors from configuring a setting's value/retrieving it.
    const nonexistent_setting = "nonexistent";
    zignix.util.settings.set(allocator, context, nonexistent_setting, "0") catch {
        const msg = context.errorMessage() catch @panic("failed to retrieve error message from context").?;
        print("error: failed to set '{s}' setting's value: {s}\n", .{ nonexistent_setting, msg.? });
    };

    const experimental_features_setting = "experimental-features";
    zignix.util.settings.set(allocator, context, experimental_features_setting, "nix-command flakes") catch {
        const msg = context.errorMessage() catch @panic("failed to retrieve error message from context").?;
        print("error: failed to set '{s}' setting's value: {s}\n", .{ experimental_features_setting, msg.? });
    };

    const experimental_features = zignix.util.settings.get(allocator, context, experimental_features_setting) catch |err| {
        if (err == error.Key) {
            print("error: setting '{s}' does not exist\n", .{experimental_features_setting});
            return 1;
        }

        unreachable;
    };
    defer allocator.free(experimental_features);
    std.debug.print("experimental features :: {s}\n", .{experimental_features});

    zignix.store.init(context, true) catch {
        const msg = context.errorMessage() catch @panic("unrecoverable error");
        print("error: failed to initialize nix store lib: {s}\n", .{msg.?});
        return 1;
    };

    const nix_store = NixStore.open(allocator, context, "", .{}) catch {
        const msg = context.errorMessage() catch @panic("failed to retrieve error message from context").?;
        print("error: failed to open Nix store: {s}\n", .{msg.?});
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

    zignix.expr.init(context) catch {
        const msg = context.errorMessage() catch @panic("unrecoverable error");
        print("error: failed to initialize nix expr lib: {s}\n", .{msg.?});
        return 1;
    };

    const eval_state = init_eval_state(allocator, context, nix_store) catch return 1;
    defer eval_state.deinit();

    print("\n", .{});

    print("1. Realising a single derivation using .drvPath\n", .{});
    print("-----------------------------------------------\n", .{});

    realise_using_drv_path(allocator, context, eval_state, nix_store) catch return 1;

    print("\n", .{});

    print("2. Realising a string context\n", .{});
    print("-----------------------------\n", .{});

    realise_using_string_context(allocator, context, eval_state, nix_store) catch return 1;

    print("Success!\n", .{});

    return 0;
}

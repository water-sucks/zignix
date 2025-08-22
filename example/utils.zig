const std = @import("std");
const posix = std.posix;
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const print = std.debug.print;

const zignix = @import("zignix");
const NixContext = zignix.NixContext;
const NixStore = zignix.store.Store;
const EvalState = zignix.expr.EvalState;
const EvalStateBuilder = zignix.expr.EvalStateBuilder;

pub fn initEvalStateFromNixPath(allocator: Allocator, context: *NixContext, store: NixStore) !EvalState {
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

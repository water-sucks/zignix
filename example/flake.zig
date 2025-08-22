const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const print = std.debug.print;

const zignix = @import("zignix");

fn initEvalState(
    allocator: Allocator,
    context: *zignix.NixContext,
    store: zignix.NixStore,
    flake_settings: *zignix.FlakeSettings,
) !zignix.EvalState {
    const builder = zignix.EvalStateBuilder.init(allocator, context, store) catch |err| {
        print("error: failed to initialize nix eval state builder: {}\n", .{err});
        return err;
    };

    builder.loadSettings(context) catch |err| {
        print("error: failed to load settings for nix eval state builder: {}\n", .{err});
        print("using default settings\n", .{});
    };

    builder.addFlakeSettings(context, flake_settings.*) catch |err| {
        print("error: failed to add flake utilities to nix eval state builder: {}\n", .{err});
        return err;
    };

    const state = builder.build(context) catch |err| {
        print("error: failed to build nix eval state: {}\n", .{err});
        return err;
    };

    return state;
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

    const context = try zignix.NixContext.init(allocator);
    defer context.deinit();

    zignix.init(context) catch {
        const msg = context.errorMessage() catch "(failed to retrieve error message from context)";
        print("error: failed to initialize nix lib: {s}", .{msg.?});
        return 1;
    };

    const nix_store = zignix.NixStore.open(allocator, context, "", .{}) catch {
        const msg = context.errorMessage() catch "(failed to retrieve error message from context)";
        print("error: failed to open nix store: {s}\n", .{msg.?});
        return 1;
    };
    defer nix_store.deinit();

    var flake_settings = try zignix.FlakeSettings.init(context);
    defer flake_settings.deinit();

    print("Using a flake and its output attributes\n", .{});
    print("---------------------------------------\n", .{});

    const eval_state = initEvalState(allocator, context, nix_store, &flake_settings) catch return 1;
    defer eval_state.deinit();

    var parse_flags = try zignix.FlakeRefParseFlags.init(allocator, context, &flake_settings, eval_state);
    defer parse_flags.deinit();

    var lock_flags = try zignix.FlakeLockFlags.init(allocator, context, &flake_settings, eval_state);
    defer lock_flags.deinit();

    const ref = try zignix.FlakeReference.fromSlice(allocator, context, "github:nixos/nixpkgs/nixos-unstable", &parse_flags);
    defer ref.deinit();

    const locked_ref = try ref.lock(context, &lock_flags);
    defer locked_ref.deinit();

    const outputs = try locked_ref.outputAttrs(context);
    defer zignix.gc.decRef(zignix.NixValue, context, outputs) catch unreachable;

    const revision = try outputs.attrByName(context, "rev");
    defer zignix.gc.decRef(zignix.NixValue, context, revision) catch unreachable;

    const rev = try revision.string(context);
    defer allocator.free(rev);

    print("revision :: {s}\n", .{rev});

    return 0;
}

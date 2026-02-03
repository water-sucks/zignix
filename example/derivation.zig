const std = @import("std");
const print = std.debug.print;
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

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

    zignix.init(context) catch {
        const msg = context.errorMessage() catch "(failed to retrieve error message from context)";
        print("error: failed to initialize nix lib: {s}", .{msg.?});
        return 1;
    };

    var nix_store = zignix.NixStore.open(allocator, context, "", .{}) catch {
        const msg = context.errorMessage() catch "(failed to retrieve error message from context)";
        print("error: failed to open Nix store: {s}\n", .{msg.?});
        return 1;
    };
    defer nix_store.deinit();

    const eval_state = try utils.initEvalStateFromNixPath(allocator, context, nix_store);
    defer eval_state.deinit();

    print("Working with derivation and store paths directly\n", .{});
    print("------------------------------------------------\n", .{});

    const drv_json_raw = try getJSONDerivationExample(allocator);
    defer allocator.free(drv_json_raw);

    const drv = zignix.Derivation.fromJSON(allocator, context, &nix_store, drv_json_raw) catch |err| {
        const msg = try context.errorMessage() orelse @panic("bruh");
        print("{s}\n", .{msg});

        return err;
    };
    defer drv.deinit();

    print("adding raw drv to store\n", .{});

    const new_path = try drv.addToStore(context, &nix_store);
    defer new_path.deinit();

    const new_path_name = try new_path.name();
    defer allocator.free(new_path_name);

    print("new path {s} added to store\n", .{new_path_name});

    return 0;
}

fn getJSONDerivationExample(allocator: Allocator) ![]const u8 {
    var child = std.process.Child.init(&.{ "nix", "derivation", "show", "nixpkgs#hello" }, allocator);

    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    var stdout = try ArrayList(u8).initCapacity(allocator, 0);
    defer stdout.deinit(allocator);

    var stderr = try ArrayList(u8).initCapacity(allocator, 0);
    defer stderr.deinit(allocator);

    try child.spawn();

    try child.collectOutput(allocator, &stdout, &stderr, std.math.maxInt(usize));

    _ = try child.wait();

    const json_output = try stdout.toOwnedSlice(allocator);
    defer allocator.free(json_output);

    return try extractDerivationKey(allocator, json_output);
}

fn extractDerivationKey(allocator: std.mem.Allocator, json_bytes: []const u8) ![]const u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{});
    defer parsed.deinit();

    var root = parsed.value;

    var derivations = root.object.get("derivations").?.object;

    var iter = derivations.iterator();

    const first = iter.next().?;
    const value = first.value_ptr.*;

    const serialized = try std.json.Stringify.valueAlloc(allocator, value, .{});

    return serialized;
}

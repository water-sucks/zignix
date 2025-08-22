const std = @import("std");
const print = std.debug.print;
const builtin = @import("builtin");

const zignix = @import("zignix");

const nonexistent_setting = "nonexistent";
const experimental_features_setting = "experimental-features";

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

    zignix.util.init(context) catch {
        const msg = context.errorMessage() catch @panic("unrecoverable error");
        print("error: failed to initialize nix utils lib: {s}", .{msg.?});
        return 1;
    };

    print("Retrieving/setting values for Nix settings\n", .{});
    print("------------------------------------------\n", .{});

    zignix.util.settings.set(allocator, context, nonexistent_setting, "0") catch {
        const msg = context.errorMessage() catch "failed to retrieve error message from context";
        print("error: failed to set value for setting '{s}': {s}\n", .{ nonexistent_setting, msg.? });
    };

    zignix.util.settings.set(allocator, context, experimental_features_setting, "nix-command flakes") catch {
        const msg = context.errorMessage() catch "failed to retrieve error message from context";
        print("error: failed to set '{s}' setting's value: {s}\n", .{ experimental_features_setting, msg.? });
    };

    _ = zignix.util.settings.get(allocator, context, nonexistent_setting) catch |err| {
        if (err == error.Key) {
            print("error: setting '{s}' does not exist\n", .{nonexistent_setting});
            return 1;
        }

        unreachable;
    };

    const experimental_features = try zignix.util.settings.get(allocator, context, experimental_features_setting);
    defer allocator.free(experimental_features);
    std.debug.print("experimental features :: {s}\n", .{experimental_features});

    return 0;

    // TODO: add an example of reading ambient settings using an EvalStateBuilder?
}

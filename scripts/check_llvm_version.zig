// Copyright 2026-2026 Rekka contributors
// Licensed under Apache License 2.0 or any later version
// Refer to the LICENSE file included.

const std = @import("std");

const llvm = @import("llvm");

pub fn main(init: std.process.Init) !void {
    const arguments = init.minimal.args.vector;
    if (arguments.len != 2) {
        const message = try std.fmt.allocPrint(init.gpa, "Usage: {s} EXPECTED_LLVM_VERSION", .{@typeName(@This())});
        defer init.gpa.free(message);
        @panic(message);
    }
    const expected: []const u8 = std.mem.span(arguments[1]);

    var major: c_uint = undefined;
    var minor: c_uint = undefined;
    var patch: c_uint = undefined;
    llvm.LLVMGetVersion(&major, &minor, &patch);

    const packed_version = .{ major, minor, patch };

    const version = try std.fmt.allocPrint(init.gpa, "{}.{}.{}", packed_version);
    defer init.gpa.free(version);
    if (std.SemanticVersion.order(try std.SemanticVersion.parse(version), try std.SemanticVersion.parse(expected)) != .eq) {
        std.log.err("The version of LLVM is \"{}.{}.{}\".", packed_version);
        std.log.err("The version of LLVM is not the version of this package (expected: {s}).", .{expected});
        std.process.exit(1);
    }
}

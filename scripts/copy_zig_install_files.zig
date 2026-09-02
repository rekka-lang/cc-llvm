// Copyright 2026-2026 Rekka contributors
// Licensed under Apache License 2.0 or any later version
// Refer to the LICENSE file included.

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const arguments = init.minimal.args.vector;
    if (arguments.len < 4) {
        const message = try std.fmt.allocPrint(init.gpa, comptime "Usage: {s} OUTPUT_DIRECTORY ZIG_INSTALL_DIRECTORY RELATIVE_FILE_TO_COPY...", .{@typeName(@This())});
        defer init.gpa.free(message);
        @panic(message);
    }

    const zig_install = try std.Io.Dir.openDirAbsolute(init.io, std.mem.span(arguments[2]), .{});
    defer zig_install.close(init.io);
    const output = try std.Io.Dir.openDirAbsolute(init.io, std.mem.span(arguments[1]), .{});
    defer output.close(init.io);
    for (arguments[3..]) |file| {
        const file_as_span = std.mem.span(file);
        try zig_install.copyFile(file_as_span, output, file_as_span, init.io, .{ .make_path = true });
    }
}

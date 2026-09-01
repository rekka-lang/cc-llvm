// Copyright 2026-2026 Rekka contributors
// Licensed under Apache License 2.0 or any later version
// Refer to the LICENSE file included.

const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/root.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_c.addIncludePath(b.path("include"));

    const module = translate_c.addModule("llvm");
    module.link_libcpp = true;

    const libraries = try std.Io.Dir.openDir(b.build_root.handle, b.graph.io, "lib", .{ .iterate = true });
    defer libraries.close(b.graph.io);
    var libraries_iterator = libraries.iterate();
    while (try libraries_iterator.next(b.graph.io)) |library| {
        _ = module.addObjectFile(b.path(b.pathJoin(&.{ "lib", library.name })));
    }

    const licenses = b.addNamedWriteFiles("licenses");
    _ = licenses.addCopyDirectory(b.path("third-party"), ".", .{});
}

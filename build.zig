// Copyright 2026-2026 Rekka contributors
// Licensed under Apache License 2.0 or any later version
// Refer to the LICENSE file included.

const std = @import("std");

const build_info = @import("build.zig.zon");
const ghoti_build_info = @import("submodules/ghoti/build.zig.zon");
const LLVMBuilder = @import("submodules/ghoti/third-party/llvm/LLVMBuilder.zig");

fn checkLlvmVersion(b: *std.Build, optimize: std.builtin.OptimizeMode) !*std.Build.Step {
    const check_llvm_version = "check_llvm_version";
    const check_llvm_version_step = b.step(check_llvm_version, "Check that the version of this package matches the version of the exposed LLVM.");

    const target = b.graph.host;
    const llvm = try createOrAddLlvmModule(struct {
        pub fn call(builder: *std.Build, _: []const u8, options: std.Build.Step.TranslateC.Options) ModuleWithTranslateC {
            const translate_c = builder.addTranslateC(options);
            return .{
                .module = translate_c.createModule(),
                .translate_c = translate_c,
            };
        }
    }.call, b, target, optimize);

    var run_check_llvm_version = b.addRunArtifact(b.addExecutable(.{
        .name = check_llvm_version,
        .root_module = b.createModule(.{
            .root_source_file = b.path(std.fmt.comptimePrint("scripts/{s}.zig", .{check_llvm_version})),
            .target = target,
            .imports = &.{
                .{ .name = llvm.name, .module = llvm.module },
            },
        }),
    }));
    run_check_llvm_version.addArg(build_info.version);

    check_llvm_version_step.dependOn(&run_check_llvm_version.step);

    return check_llvm_version_step;
}

fn addLicenses(b: *std.Build, target: std.Target) !*std.Build.Step.WriteFile {
    const licenses = b.addNamedWriteFiles("licenses");

    const llvm = b.dependency("llvm", .{});
    _ = licenses.addCopyFile(b.path("LICENSE"), "cc-llvm");
    _ = licenses.addCopyFile(llvm.path("LICENSE.TXT"), "LLVM.TXT");
    _ = licenses.addCopyFile(llvm.path("llvm/include/llvm/Support/LICENSE.TXT"), "LLVM System Interface Library.TXT");
    _ = licenses.addCopyFile(llvm.path("llvm/lib/Support/BLAKE3/LICENSE"), "BLAKE3");
    _ = licenses.addCopyFile(b.dependency("zlib", .{}).path("LICENSE"), "zlib");
    _ = licenses.addCopyFile(b.dependency("libxml2", .{}).path("Copyright"), "libxml2");
    _ = licenses.addCopyFile(b.dependency("zstd", .{}).path("LICENSE"), "zstd");

    var run_copy_zig_install_files = b.addRunArtifact(b.addExecutable(.{
        .name = "copy_zig_install_files",
        .root_module = b.createModule(.{
            .root_source_file = b.path("scripts/copy_zig_install_files.zig"),
            .target = b.graph.host,
        }),
    }));
    const zig_with_licenses_only = run_copy_zig_install_files.addOutputDirectoryArg("zig");
    run_copy_zig_install_files.addArg(std.Build.LazyPath.dirname(.{ .cwd_relative = b.graph.zig_lib_directory.path orelse @panic("Unknown zig library directory") }).getDisplayName());

    var zig_licenses: std.ArrayList(struct { path: []const u8, final_name: []const u8 }) = .empty;
    defer zig_licenses.deinit(b.allocator);
    try zig_licenses.appendSlice(b.allocator, &.{
        .{ .path = "LICENSE", .final_name = "zig" },
        .{ .path = "lib/libcxx/LICENSE.TXT", .final_name = "libcxx.TXT" },
        .{ .path = "lib/libcxxabi/LICENSE.TXT", .final_name = "libcxxabi.TXT" },
        .{ .path = "lib/libunwind/LICENSE.TXT", .final_name = "libunwind.TXT" },
    });
    if (target.isMuslLibC()) {
        try zig_licenses.append(b.allocator, .{ .path = "lib/libc/musl/COPYRIGHT", .final_name = "musl" });
    } else if (target.isGnuLibC()) {
        try zig_licenses.append(b.allocator, .{ .path = "lib/libc/glibc/LICENSES", .final_name = "glibc" });
    } else if (target.isMinGW()) {
        try zig_licenses.append(b.allocator, .{ .path = "lib/libc/mingw/COPYING", .final_name = "mingw" });
    } else {
        const message = try std.fmt.allocPrint(b.allocator, "The copy of {} libc's license is not implemented", .{target.abi});
        defer b.allocator.free(message);
        @panic(message);
    }

    for (zig_licenses.items) |license| {
        run_copy_zig_install_files.addArg(license.path);

        _ = licenses.addCopyFile(zig_with_licenses_only.path(b, license.path), license.final_name);
    }

    return licenses;
}

fn buildLtoFromTools(builder: *LLVMBuilder) *std.Build.Step.Compile {
    return builder.createLLVMLibrary(.{ .name = "LTO", .cxx_source_files = .{
        .root = builder.metadata.root.path(builder.b, "llvm/tools/lto"),
        .files = &.{
            "LTODisassembler.cpp",
            "lto.cpp",
        },
    }, .additional_include_paths = &.{
        builder.target_artifacts.intrinsics_gen.getDirectory(),
        builder.configure_phase_artifacts.gen_vt.getDirectory(),
        builder.metadata.extension_def.getDirectory(),
    }, .config_headers = &.{
        builder.target_artifacts.config_headers.disassemblers_def,
        builder.target_artifacts.config_headers.asm_printers_def,
        builder.target_artifacts.config_headers.asm_parsers_def,
        builder.target_artifacts.config_headers.target_mcas_def,
        builder.target_artifacts.config_headers.abi_breaking_h,
        builder.target_artifacts.config_headers.llvm_config_h,
        builder.target_artifacts.config_headers.targets_def,
    } });
}

const ModuleWithName = struct {
    name: []const u8,
    module: *std.Build.Module,
};

const ModuleWithTranslateC = struct {
    module: *std.Build.Module,
    translate_c: *std.Build.Step.TranslateC,
};

const CreateOrAddModule = fn (*std.Build, []const u8, std.Build.Step.TranslateC.Options) ModuleWithTranslateC;

fn createOrAddLlvmModule(createOrAddModule: *const CreateOrAddModule, b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !ModuleWithName {
    const llvm_builder = LLVMBuilder.init(b, .{ .optimize = optimize });
    llvm_builder.build(.{
        // Do not build kaleidoscope
        .behavior = .package,
        .target = target,
    });

    const name = "llvm";
    const moduleWithTranslateC = createOrAddModule(b, name, .{
        .root_source_file = b.path("src/root.h"),
        .target = target,
        .optimize = optimize,
    });

    const llvm_include_paths = llvm_builder.allIncludePaths();
    for (llvm_include_paths.includes) |include| {
        moduleWithTranslateC.translate_c.addIncludePath(include);
    }
    for (llvm_include_paths.config_headers) |config_header| {
        moduleWithTranslateC.translate_c.addConfigHeader(config_header);
    }
    // TODO: Create a PR to add it to ghoti ?
    moduleWithTranslateC.translate_c.addConfigHeader(llvm_builder.target_artifacts.config_headers.disassemblers_def);
    moduleWithTranslateC.translate_c.addConfigHeader(llvm_builder.target_artifacts.config_headers.asm_printers_def);
    moduleWithTranslateC.translate_c.addConfigHeader(llvm_builder.target_artifacts.config_headers.asm_parsers_def);
    moduleWithTranslateC.translate_c.addConfigHeader(llvm_builder.target_artifacts.config_headers.llvm_config_h);
    moduleWithTranslateC.translate_c.addConfigHeader(llvm_builder.target_artifacts.config_headers.targets_def);

    moduleWithTranslateC.module.link_libcpp = true;
    for (llvm_builder.allTargetArtifacts()) |artifact| {
        moduleWithTranslateC.module.linkLibrary(artifact);
    }
    // TODO: Create a PR to add it to ghoti ?
    moduleWithTranslateC.module.linkLibrary(buildLtoFromTools(llvm_builder));

    return .{
        .name = name,
        .module = moduleWithTranslateC.module,
    };
}

fn checkGhotiDependencies(b: *std.Build) !*std.Build.Step {
    const check_ghoti_dependencies = b.step("check_ghoti_dependencies", "Check that the ghoti dependencies defined in build.zig.zon are the same as the ones in the submodule.");
    check_ghoti_dependencies.makeFn = struct {
        pub fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) !void {
            inline for (std.meta.fields(@TypeOf(build_info.dependencies))) |dependency_field| {
                const dependency = @field(build_info.dependencies, dependency_field.name);

                if (@hasField(@TypeOf(ghoti_build_info.dependencies), dependency_field.name)) {
                    const ghoti_dependency = @field(ghoti_build_info.dependencies, dependency_field.name);

                    if (!std.mem.eql(u8, dependency.url, ghoti_dependency.url)) {
                        return step.fail("'{s}' dependency should have the url defined in ghoti's build.zig.zon: {s}", .{ dependency_field.name, ghoti_dependency.url });
                    }
                }
            }
        }
    }.make;

    return check_ghoti_dependencies;
}

const BuildZigZonName = enum {
    cc_llvm,
    cc_llvm_x86_64_linux_musl,
    cc_llvm_x86_64_linux_gnu,
    cc_llvm_x86_64_windows_gnu,
};

const BuildZigZon = struct {
    name: BuildZigZonName,
    version: []const u8,
    fingerprint: u64,
    minimum_zig_version: []const u8,
    dependencies: struct {},
    paths: []const []const u8,
};

fn checkInstallBuildZigZonFiles(b: *std.Build) !*std.Build.Step {
    const check = b.step("check_install_build.zig.zon_files", "Check that the install build.zig.zon files have the correct information.");
    check.makeFn = struct {
        pub fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) !void {
            const files: []const BuildZigZon = &.{
                @import("install/build-x86_64-linux-musl.zig.zon"),
                @import("install/build-x86_64-linux-gnu.zig.zon"),
                @import("install/build-x86_64-windows-gnu.zig.zon"),
            };

            var fingerprints: std.AutoHashMap(u64, void) = .init(step.owner.allocator);
            defer fingerprints.deinit();
            try fingerprints.put(build_info.fingerprint, {});

            var names: std.EnumMap(BuildZigZonName, void) = .init(.{});
            names.put(build_info.name, {});

            for (files) |file| {
                try fingerprints.put(file.fingerprint, {});
                names.put(file.name, {});

                if (!std.mem.eql(u8, file.version, build_info.version)) {
                    return step.fail("'{}' should have the version: {s}", .{ file.name, build_info.version });
                }
                if (!std.mem.eql(u8, file.minimum_zig_version, build_info.minimum_zig_version)) {
                    return step.fail("'{}' should have the minimum_zig_version: {s}", .{ file.name, build_info.minimum_zig_version });
                }
            }

            if (fingerprints.count() != (files.len + 1)) {
                return step.fail("There is a duplicate fingerprint in a build.zig.zon", .{});
            }
            if (names.count() != (files.len + 1)) {
                return step.fail("There is a duplicate name in a build.zig.zon", .{});
            }

            const install_directory = try std.Io.Dir.openDir(step.owner.build_root.handle, step.owner.graph.io, "install", .{ .iterate = true });
            defer install_directory.close(step.owner.graph.io);

            var install_directory_iterator = install_directory.iterate();
            var zigZonFilesCount: u8 = 0;
            while (try install_directory_iterator.next(step.owner.graph.io)) |entry| {
                if (std.mem.endsWith(u8, entry.name, ".zig.zon")) {
                    zigZonFilesCount += 1;
                }
            }

            if (files.len != zigZonFilesCount) {
                return step.fail("Not all install build.zig.zon files are checked", .{});
            }
        }
    }.make;

    return check;
}

fn addCheckStep(b: *std.Build, optimize: std.builtin.OptimizeMode) !void {
    const checks: []const *std.Build.Step = &.{
        try checkLlvmVersion(b, optimize),
        try checkGhotiDependencies(b),
        try checkInstallBuildZigZonFiles(b),
    };

    var description: std.ArrayList(u8) = .empty;
    defer description.deinit(b.allocator);
    try description.appendSlice(b.allocator, "Run the following checks:");
    for (checks, 0..) |check, i| {
        try description.appendSlice(b.allocator, if (i == 0) " " else ", ");
        try description.appendSlice(b.allocator, check.name);
    }

    const step = b.step("check", description.items);
    for (checks) |check| {
        step.dependOn(check);
    }
}

fn install(b: *std.Build, module: *std.Build.Module, licenses: *std.Build.Step.WriteFile, target: std.Target.Query) !void {
    const triple = try target.zigTriple(b.allocator);
    defer b.allocator.free(triple);

    const step = b.getInstallStep();
    for (module.link_objects.items) |library| {
        switch (library) {
            .other_step => |compile| step.dependOn(&b.addInstallArtifact(compile, .{
                .dest_dir = .{ .override = .{ .custom = b.pathJoin(&.{ triple, "lib" }) } },
                .h_dir = .{ .override = .{ .custom = b.pathJoin(&.{ triple, "include" }) } },
            }).step),
            .assembly_file => @panic("The copy from a 'assembly_file' LinkObject is not implemented"),
            .c_source_file => @panic("The copy from a 'c_source_file' LinkObject is not implemented"),
            .c_source_files => @panic("The copy from a 'c_source_files' LinkObject is not implemented"),
            .static_path => @panic("The copy from a 'static_path' LinkObject is not implemented"),
            .system_lib => @panic("The copy from a 'system_lib' LinkObject is not implemented"),
            .win32_resource_file => @panic("The copy from a 'win32_resource_file' LinkObject is not implemented"),
        }
    }

    const install_dir: std.Build.InstallDir = .{ .custom = triple };
    step.dependOn(&b.addInstallDirectory(.{
        .source_dir = licenses.getDirectory(),
        .install_dir = install_dir,
        .install_subdir = "third-party",
    }).step);

    step.dependOn(&b.addInstallDirectory(.{
        .source_dir = b.path("src"),
        .install_dir = install_dir,
        .install_subdir = "src",
    }).step);

    step.dependOn(&b.addInstallDirectory(.{
        .install_dir = install_dir,
        .install_subdir = b.pathJoin(&.{ "include", "llvm-c" }),
        .source_dir = b.dependency("llvm", .{}).path("llvm/include/llvm-c"),
    }).step);

    step.dependOn(&b.addInstallFileWithDir(b.path("install/build.zig"), install_dir, "build.zig").step);
    const build_zig_zon = try std.fmt.allocPrint(b.allocator, "install/build-{s}.zig.zon", .{triple});
    defer b.allocator.free(build_zig_zon);
    step.dependOn(&b.addInstallFileWithDir(b.path(build_zig_zon), install_dir, "build.zig.zon").step);

    step.dependOn(&b.addInstallFileWithDir(b.path("LICENSE"), install_dir, "LICENSE").step);
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const moduleWithName = try createOrAddLlvmModule(struct {
        pub fn call(builder: *std.Build, name: []const u8, options: std.Build.Step.TranslateC.Options) ModuleWithTranslateC {
            const translate_c = builder.addTranslateC(options);
            return .{
                .module = translate_c.addModule(name),
                .translate_c = translate_c,
            };
        }
    }.call, b, target, optimize);

    const licenses = try addLicenses(b, target.result);

    try install(b, moduleWithName.module, licenses, target.query);

    try addCheckStep(b, optimize);
}

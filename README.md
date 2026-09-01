# Cross-compiled LLVM

[![Continuous Integration](https://github.com/rekka-lang/cc-llvm/actions/workflows/ci.yml/badge.svg?branch=develop)](https://github.com/rekka-lang/cc-llvm/actions/workflows/ci.yml)

A library exposing the C API of LLVM and offering cross-compilation thanks to [Zig](https://ziglang.org/). It mainly relies on the work done by [Trevor Swan](https://github.com/trevorswan11) for [ghoti](https://github.com/trevorswan11/ghoti).

## Getting started

### Installation

Use `zig fetch`.

```bash
zig fetch --save https://github.com/rekka-lang/cc-llvm/releases/download/v21.1.8+1/source.zip
```

You can also add a compiled version of the library to reduce the build time. Here is the command to install the library built for `x86_64-linux-musl`.

```bash
zig fetch --save https://github.com/rekka-lang/cc-llvm/releases/download/v21.1.8+1/x86_64-linux-musl.zip
```

Please refer to the GitHub release to see the available compiled versions.

### Usage

Import the module in your `build.zig`.
```zig
fn ccLlvmDependency(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Dependency {
    const triple = std.Target.Query.zigTriple(target.query, b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);
    std.mem.replaceScalar(u8, triple, '-', '_');

    const name = std.fmt.allocPrint(b.allocator, "cc_llvm_{s}", .{ triple }) catch @panic("OOM");
    defer b.allocator.free(name);
    for (b.available_deps) |dependency| {
        if (std.mem.eql(u8, dependency.@"0", name)) {
            return b.dependency(name, .{ .target = target, .optimize = optimize });
        }
    }

    return b.dependency("cc_llvm", .{ .target = target, .optimize = optimize });
}

pub fn build(b: *std.Build) void {
    ...

    const cc_llvm = ccLlvmDependency(b, target, optimize);

    your_module.addImport("llvm", cc_llvm.module("llvm"));
}
```

There is also a `WriteFiles` containing all the license files that you have to distribute.
```zig
b.installDirectory(.{
    .install_dir = .bin,
    .install_subdir = "third-party",
    .source_dir = cc_llvm.namedWriteFiles("licenses").getDirectory(),
});
```

Here is a little snippet of an API call:
```zig
const std = @import("std");

const llvm = @import("llvm");

pub fn main(_: std.process.Init) !void {
    var major: c_uint = undefined;
    var minor: c_uint = undefined;
    var patch: c_uint = undefined;
    llvm.LLVMGetVersion(&major, &minor, &patch);

    std.log.info("The version of LLVM is \"{}.{}.{}\".", .{ major, minor, patch });
}
```

## Contributing

Please see [Contributing](./CONTRIBUTING.md) for more information on how to get involved.

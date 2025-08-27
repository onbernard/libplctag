# libplctag zig

This is libplctag ported to the Zig Build System.

## Use

Add the dependency in your `build.zig.zon` by running the following command:

```
zig fetch --save git+https://github.com/onbernard/libplctag
```

Then in your `build.zig`:

```zig
const plctag = b.dependency("libplctag", .{ .target = target, .optimize = optimize });
exe.linkLibrary(plctag.artifact("plctag"));
```

## targets matrix

### Supported targets

| target             | state | note                  |
| ------------------ | ----- | --------------------- |
| x86_64-linux       | ✅    |                       |
| x86-linux          | ✅    |                       |
| x86_64-macos       | ✅    |                       |
| aarch64-macos      | ✅    |                       |
| x86_64-windows-gnu | ✅    | shims for linux hosts |

## Flags

All `-std=c11`

### Any non Windows

| target       | release | flags                                                                         |
| ------------ | ------- | ----------------------------------------------------------------------------- |
| gcc or clang |         | -D__USE_POSIX=1 -D_XOPEN_SOURCE=700 -D_POSIX_C_SOURCE=200809L                 |
|              |         | -Wall -pedantic -Wextra -Wconversion -fno-strict-aliasing -fvisibility=hidden |
| any apple    |         | -D_DARWIN_C_SOURCE                                                            |
| 32bits       |         | -m32                                                                          |
|              | Debug   | -O0 -g -fno-omit-frame-pointer                                                |
|              | Small   | -Os -DNDEBUG                                                                  |

### Windows

| target              | release | flags                                                                |
| ------------------- | ------- | -------------------------------------------------------------------- |
| mingw               |         | -DMINGW=1                                                            |
| x86_64-windows-msvc |         | -DPLATFORM_WINDOWS=1 -DWIN32_LEAN_AND_MEAN -D_CRT_SECURE_NO_WARNINGS |

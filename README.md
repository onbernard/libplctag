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

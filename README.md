# `zenith` - Reach Zenith of Zig Performance

`zenith` is a micro benchmarking library for the Zig programming language.

## Features

* Ergonomic: easy to use, no boilerplate
* Robust: even in noisy environments
* Configurable: to meets your needs

## Writing Your First Benchmark

Let's say we want to compare performance of 2 functions that compute the nth
number of the Fibonacci sequence. We have a recursive and an iterative version:

```zig
fn fibRecursive(n: usize) usize {
    if (n < 2) return n;
    return fibRecursive(n - 2) + fibRecursive(n - 1);
}

fn fibIterative(n: usize) usize {
    if (n < 2) return n;

    var prev: usize = 0;
    var last: usize = 1;

    for (2..n + 1) |_| {
        const next = last + prev;
        prev = last;
        last = next;
    }

    return last;
}
```

Typical micro benchmarks are structured like:

```zig
fn benchmark(m: *const zenith.M) {
    // setup
    // ...

    while (m.loop()) {
        // code to measure
    }

    // cleanup
    // ...
}
```

In our case:

```zig
fn benchFibIterative(m: *const zenith.M) void {
    while (m.loop()) {
        zenith.blackHole(fibIterative(zenith.blackBox(usize, &30)));
    }
}
```

`blackBox` and `blackHole` functions are used to prevent the compiler from
optimizing function argument and result respectively.

To reduce boilerplate code, you can use function `microBenchFn` to generate the
benchmark function for you:

```zig
const benchFibIterative: fn (*const zenith.M) void = zenith.microBenchFn(fibIterative, .{30});
```

Finally, run the benchmarks in a test:

```zig
test "benchmark" {
    try zenith.microBenchNamespace(struct {
        // Declarations MUST be public.
        pub const benchFibIterative: fn (*const zenith.M) void = zenith.microBenchFn(fibIterative, .{30});
        pub const benchFibRecursive: fn (*const zenith.M) void = zenith.microBenchFn(fibRecursive, .{30});
    });
}
```

And execute the tests and benchmarks using `-Dbench` (see the example
[`build.zig`](./examples/fib/build.zig)):

```bash
$ zig build test -Doptimize=ReleaseFast -Dbench
cpu: znver4
arch: x86_64
features: 64bit adx aes allow_light_256_bit avx avx2 avx512bf16 avx512bitalg avx512bw avx512cd avx512dq avx512f avx512ifma avx512vbmi avx512vbmi2 avx512vl avx512vnni avx512vpopcnt
dq bmi bmi2 branchfusion clflushopt clwb clzero cmov crc32 cx16 cx8 evex512 f16c fast_15bytenop fast_bextr fast_dpwssd fast_imm16 fast_lzcnt fast_movbe fast_scalar_fsqrt fast_scal
ar_shift_masks fast_variable_perlane_shuffle fast_vector_fsqrt fma fsgsbase fsrm fxsr gfni idivq_to_divl invpcid lzcnt macrofusion mmx movbe mwaitx nopl pclmul pku popcnt prfchw r
dpid rdpru rdrnd rdseed sahf sbb_dep_breaking sha shstk slow_shld smap smep sse sse2 sse3 sse4_1 sse4_2 sse4a ssse3 vaes vpclmulqdq vzeroupper wbnoinvd x87 xsave xsavec xsaveopt x
saves
os: linux
abi: gnu
system clock precision: 1.187us

FibIterative    1.484us/op      0 alloc/op (0 bytes/op)
FibRecursive    2.568ms/op      0 alloc/op (0 bytes/op)
```

## Installation

Fetch and add `zenith` as a lazy dependency:

```bash
$ zig fetch --save=zenith git+https://github.com/negrel/zenith.git
info: resolved to commit a1a62dc499a8916d6e31e2d1373ef197df54f121
```

Edit your `build.zig.zon` and sets lazy to true:

```diff
     .dependencies = .{
         .zenith = .{
             .url = "git+https://github.com/negrel/zenith.git#a1a62dc499a8916d6e31e2d1373ef197df54f121",
             .hash = "zenith-0.1.0-AG3XSTdZAACqKrUeu3IjVqFJgF3rTOY77PZhgUYj3YTn",
+            .lazy = true,
         },
     },
```

Edit your `build.zig` to add `zenith` module:

```diff
+    // Add a bench build option.
+    const bench = b.option(bool, "bench", "Run benchmarks") orelse false;
+
+    if (b.lazyDependency("zenith", .{
+        .target = target,
+        .optimize = optimize,
+        .run = bench, // See build options section below.
+    })) |dep| {
+        mod_tests.root_module.addImport("zenith", dep.module("zenith"));
+    }
+
```

Add your first benchmark to `src/root.zig`:

```diff
 test "basic add functionality" {
     try std.testing.expect(add(3, 7) == 10);
 }
+
+const zenith = @import("zenith");
+
+pub const benchmarkAdd = zenith.microBenchFn(add, .{ 1, 2 });
+
+test "benchmark" {
+    try zenith.microBenchNamespace(@This());
+}
```

## Build Options

| Option name | Default value | Description |
|:-----------:|:-------------:|:-----------:|
|         run |       `false` | Whether benchmarks should be executed or skipped. |
| sample_count_min | `1` | Minimum number of samples per benchmark. |
| sample_count_max | `null` | Maximum number of samples per benchmark. |
| duration_ms_max | `1_000` | Maximum number of millisecond per benchmark. |
| allow_debug | `false` | Allow benchmarks to run in debug mode. |

## Acknowledgment

This library is inspired by [`Divan`](https://github.com/nvzqz/divan),
[`BenchmarkTools.jl`](https://github.com/JuliaCI/BenchmarkTools.jl) and
the [`Robust benchmarking in noisy environments`](https://arxiv.org/pdf/1608.04295)
paper behind those libraries.

The API is also inspired by Go's [`testing`](https://pkg.go.dev/testing)
standard library package.

## Contributing

If you want to contribute to `zenith` to add a feature or improve the code contact
me at [alexandre@negrel.dev](mailto:alexandre@negrel.dev), open an
[issue](https://github.com/negrel/zenith/issues) or make a
[pull request](https://github.com/negrel/zenith/pulls).

## :stars: Show Your Support

Please give a :star: if this project helped you!

[![buy me a coffee](https://github.com/negrel/.github/blob/master/.github/images/bmc-button.png?raw=true)](https://www.buymeacoffee.com/negrel)

## :scroll: License

MIT © [Alexandre Negrel](https://www.negrel.dev/)

# Zig 0.16

Read this before writing any code. Where it and CLAUDE.md disagree, CLAUDE.md
(the project's rules) wins.

## Zig 0.16.0 — Core Mental Model

**What Zig is:** A general-purpose, systems programming language with *zero hidden control flow*. No exceptions, no operator overloading, no implicit conversions, no garbage collector, no preprocessor. Everything is explicit. The compiler is self-hosted (5 MiB binary, no LLVM dependency at runtime) and cross-compiles to 40+ targets out of the box.

**The Zen (design principles, in priority order):**
- Communicate intent precisely
- Edge cases matter
- Favor reading code over writing code
- There is an idiomatic way to do things
- Runtime crashes are better than bugs
- Compile errors are better than runtime crashes
- Incremental improvements
- Avoid local maximums
- Reduce the amount one must remember
- Focus on logic, not style
- Resource allocation may fail; resource deallocation must succeed
- Memory is a resource

## 0.16.0 Headline Features

| Feature | What it means for you |
|---------|----------------------|
| **`std.Io` interface** | I/O is now an interface with `Future`, `Group`, `Cancelation`, and `Batch` primitives. Backed by io_uring (Linux) or GCD (macOS). **Function coloring is gone** — you no longer need `fn` vs `async fn` split. |
| **Juicy Main** | `main()` can accept injected dependencies (process info, env vars, args) instead of reading globals. Env vars and process args are no longer global. |
| **Type resolution redesign** | Compiler uses a DAG (not cyclic graph) with lazy field analysis. Better error messages, faster incremental builds (~12% faster ReleaseFast emission). |
| **Package management** | Dependencies live in a local `zig-pkg/` directory (not hidden `.zig-cache`). Global compressed cache. `--fork` flag for testing fixes across the dependency tree. |
| **`heap.ArenaAllocator`** | Now thread-safe and lock-free. `heap.ThreadSafeAllocator` is removed. |
| **Removed APIs** | `GenericReader`, `AnyReader`, `FixedBufferStream`, `posix`/`os.windows` modules, `@cImport` (migrating to build-system C translation). |
| **Self-hosted backends** | New ELF linker, x86 and aarch64 backends, incremental compilation. aarch64 becomes the default debug backend. |
| **Language changes** | `switch` on error unions fixed, vectors forbid runtime indexes, packed structs/unions forbid pointers, comptime-only type pointers are no longer comptime-only, zero-bit tuple fields no longer implicitly comptime. |

## Modularity

- **No global state by default.** Every function takes what it needs as parameters.
- **Explicit imports.** `const std = @import("std");` — no implicit namespace pollution.
- **Comptime generics** replace both C preprocessor and C++ templates: the *same language* runs at compile time.
- **First-class C interop:** call C functions, link C libraries, be called from C, share the C ABI — no FFI ceremony.
- **Build system is Zig code** (`build.zig`), not a config file. Packages are URLs to compressed archives; 0.16 adds local override and project-local fetch.

## Expressiveness

- **Tagged unions** for mutually exclusive states (prevents invalid combinations).
- **Error sets** as first-class types: `fn foo() MyErrorSet!T` documents exactly what can fail.
- **Optional types** (`?T`) instead of null pointers — unadorned pointers cannot be null.
- **Comptime**: `comptime T: type` for type-level generics, `comptime` blocks for compile-time computation, `@TypeOf`, `@This()`, `@field`, `@enumTypeFromInt`, etc.
- **Vectors** (`@Vector(N, T)`) for SIMD. Here they are spelled through
  `core/math.zig`: `m.Vec(t,s)` for vectors whose lanes are summed together,
  `m.Vice(t,s)` for a plain row `[s]t` (GPU and save layouts, tables,
  lanes picked by a runtime index), `m.Mat(t,s,a)` for `a` columns of
  `Vec(t,s)`. Never a bare `@Vector` or small `[N]T`. A `Vec` of any
  width has `sumOf`, `meanOf` (of many), `lenOf` and `splatOf`; points have
  `dist`; a ramp read back is `unlerp`; easing toward a target is `damp`
  (`dampV`, `dampBy`), never `x+=(t-x)*@min(1,dt*k)`.
- **Packed structs/unions** for bit-level layout.
- **`anytype`** for ad-hoc polymorphism (use sparingly).

## Ease of Use (0.16 specifically)

- **Async without coloring:** one function signature works for both sync and async I/O via the `std.Io` interface.
- **Juicy Main** eliminates the "read globals in main" boilerplate.
- **Faster iteration:** incremental compilation, 20s self-hosted build (was 75s), 5 MiB compiler binary.
- **Better errors:** the type-resolution redesign produces messages that tell you *what you actually did wrong*.
- **Never run `zig fmt`** here: the project's own style (CLAUDE.md, Style) is
  tighter than it, and `zig fmt` would undo it.

---

## What NOT To Do (Code Conventions, Not Styling)

### Memory & Resources
- **Pass allocators explicitly** to every function that allocates. No global allocator.
- **`defer` immediately after acquisition.** If you `alloc`, the `defer free` is on the next line.
- **`errdefer` for error-path cleanup**, `defer` for unconditional cleanup.
- **Use arena allocators** for batch/temporary work (free everything at once).
- **Use `std.testing.allocator` in tests** — it reports leaks with stack traces.
- **Never ignore a resource.** "Resource deallocation must succeed."
- **Avoid storing a pointer and length separately** — use a slice (`[]T`).
- **Don't mutate an `ArrayList` while iterating** over it (changes what `.items` refers to).

### Error Handling
- **Avoid `anyerror`** in public APIs. Use named error sets.
- **`catch` expressions must capture and handle the error.** Never `catch |_| {}`.
- **Don't use `orelse unreachable`** — handle the error or propagate it.
- **Don't use `handleOom`** in a function whose error set includes `error.OutOfMemory`.
- **Prefer `!T` return type** (let the compiler infer the error set) over `anyerror!T`.
- **For "should never fail" allocations**, `catch unreachable` is acceptable.

### Types & Comptime
- **Prefer `comptime T: type` over `anytype`** — explicit types produce clearer errors and let the compiler verify constraints.
- **Use `anytype` only for genuinely polymorphic cases** (callbacks, `std.debug.print`-style).
- **Avoid `undefined`** unless the value is guaranteed to be set before read.
- **Prefer `const` over `var`** always.
- **Prefer slices over raw pointers** for strings and collections.
- **Use optional types (`?T`)** instead of null pointers.
- **Exhaustive `switch`:** cover all cases or use `else => unreachable` for truly impossible cases.
- **Avoid force-unwrapping with `.?`** unless you can prove non-null.
- **Avoid `@intCast` after a manual range check** — redundant.
- **Minimize untagged unions** — they're a footgun.

### Functions & Design
- **Don't use `bool` parameters** — use enums or separate functions.
- **Don't use `inline fn`** unless *semantic* inlining is required (e.g., `@compileError`).
- **Don't use out-parameters** — return values instead.
- **Don't make functions unnecessarily `pub`** — minimize the public surface.
- **`pub` imports (re-exports) are fine here**: modules are moving to depend
  on **one** module that gathers every import into a single file.
- **Avoid `@fieldParentPtr`** when possible.
- **Avoid self-references** in structs (storing `*Self` inside `Self`).
- **Functions shouldn't take a large number of parameters** — group into a struct.
- **Avoid writing huge functions** — extract cohesive units.

### Concurrency & I/O (0.16)
- **Don't use the old `async`/`await` + `Promise` model** — it's replaced by `std.Io` with `Future`/`Group`.
- **Don't overuse async for CPU-bound tasks** — it adds overhead with no benefit.
- **Use `Group`** for fan-out/fan-in concurrent work; **`Future`** for single deferred operations; **`Batch`** for bounded concurrency.

### Integer Arithmetic
- **Integer overflow is checked in debug, undefined in release.** Use wrapping arithmetic (`+%`, `-%`, `*%`) when overflow is intentional. Use saturating (`+|`, `-|`, `*|`) for bounds clamping.

### General
- **No closures** — Zig doesn't have them. Use function pointers or comptime.
- **No operator overloading** — use named methods.
- **No hidden control flow** — no exceptions, no implicit conversions, no destructors.
- **Don't shadow identifiers** from outer scopes (compile error).
- **Larger cohesive files are idiomatic** — tests alongside implementation, comptime generics at file scope. Don't split files into tightly coupled pieces.

---

## Zig 0.16 for Games

**Directly beneficial:**
- **`@floor`, `@ceil`, `@round`, `@trunc`** replacing `@intFromFloat` — the release notes say this is *"part of a larger effort to improve ergonomics for making video games in Zig."* Position/velocity math is cleaner.
- **Small integers auto-coerce to floats** — a `u8` pixel coordinate can now be used where an `f32` is expected without a cast.
- **`std.Io` + `Juicy Main`** — asset loading, audio, network, and input all flow through the `Io` interface. The [Aether game engine](https://github.com/AetherEngine/Aether) already uses `io.async`, `io.concurrent`, and `std.Io.Group` for its fixed-step loop (144 Hz update / uncapped render). You pick a threaded or evented backend without rewriting game code.
- **Faster incremental compilation** — shorter edit-test loop for the game loop itself.

**Breaking / requires migration:**
- **Vectors forbid runtime indexes** (`my_vec[99]` no longer compiles) — affects SIMD math in `zmath` and any hand-rolled vector code. You must use comptime indices or fall back to regular arrays.
- **`@cImport` removed** — game dev leans heavily on C interop (Vulkan, OpenGL, SDL, GLFW, Bullet/Jolt physics). You must migrate to `b.addTranslateC` in `build.zig`.
- **`Io` object passed to everything with side effects** — asset loaders, audio (`zaudio`), input (`zglfw`/`zsdl`), and network all now take `io: Io` as a parameter. The [zig-gamedev](https://github.com/zig-gamedev) org's libraries (zgpu, zaudio, zglfw, zsdl, zphysics, zmath, etc.) are actively being updated (last commits Oct 2026).
- **`GenericReader`/`AnyReader` deleted** — any custom asset pipeline using those is broken.

**Practical conventions for game code specifically:**
| Concern | What to do |
|---------|-----------|
| Game loop I/O | Pass `io: Io` to your update/render functions; use `io.sleep` for frame pacing, `io.async` for background asset loading |
| Asset loading | Use `io.async` + `Io.Group` for parallel loads (textures, audio, meshes); don't block the main thread |
| Audio | `zaudio` (miniaudio bindings) — will need `Io` parameter going forward |
| Math | `zmath` for SIMD; remember comptime-only vector indexing in 0.16 |
| C libraries (Vulkan, SDL, physics) | Use `b.addTranslateC` in `build.zig`, not `@cImport` |
| Frame timing | `io.sleep(.fromMicroseconds(...), .awake)` — the Io interface replaces `std.time.sleep` |
| ECS / job systems | `zjobs` (job queue) or `Io.Group` for fan-out; `zpool` for object pooling |

**Ecosystem reality:** The community is still small — a few people working on games in Zig at a commercial level. The [zig-gamedev](https://github.com/zig-gamedev) org is the main hub. Most practical game dev in Zig still means "Zig + C bindings" rather than pure-Zig libraries.

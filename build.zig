const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const use_semaphore = b.option(bool, "use_semaphore", "should a semaphore be used") orelse false;
    const use_lfqueue = b.option(bool, "use_lfqueue", "should a lfqueue be used") orelse false;

    const actor_options = b.addOptions();
    actor_options.addOption(bool, "use_semaphore", use_semaphore);
    actor_options.addOption(bool, "use_lfqueue", use_lfqueue);

    const clap = b.createModule(.{
        .root_source_file = .{ .path = "extern/zig-clap/clap.zig" },
        .target = target,
        .optimize = optimize,
    });

    const ztracy = b.dependency("ztracy", .{
        .enable_ztracy = true,
        .enable_fibers = false,
    });
    const ztracy_module = ztracy.module("root");

    const helper = b.createModule(.{
        .root_source_file = .{ .path = "modules/helper/helper.zig" },
        .target = target,
        .optimize = optimize,
    });
    helper.addImport("ztracy", ztracy_module);

    const containers = b.createModule(.{
        .root_source_file = .{ .path = "modules/containers/containers.zig" },
        .target = target,
        .optimize = optimize,
    });
    containers.addImport("ztracy", ztracy_module);

    const release_flags = [_][]const u8{};
    const debug_flags = [_][]const u8{"-O3"};
    const flags = if (optimize == .Debug) &debug_flags else &release_flags;

    containers.addIncludePath(.{ .path = "extern/concurrentqueue" });
    containers.addIncludePath(.{ .path = "extern/concurrentqueue/c_api" });
    containers.addIncludePath(.{ .path = "extern/concurrentqueue/internal" });
    containers.addCSourceFile(.{
        .file = .{ .path = "extern/concurrentqueue/c_api/concurrentqueue.cpp" },
        .flags = flags,
    });

    const actor = b.createModule(.{
        .root_source_file = .{ .path = "modules/actor/actor.zig" },
        .target = target,
        .optimize = optimize,
    });
    if (target.result.os.tag == .windows) {
        actor.addIncludePath(.{ .path = "c/win" });
    } else {
        actor.addIncludePath(.{ .path = "c/linux" });
    }
    actor.addImport("helper", helper);
    actor.addImport("containers", containers);
    actor.addImport("ztracy", ztracy_module);
    actor.addOptions("config", actor_options);

    const exe = b.addExecutable(.{
        .name = "abps",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("ztracy", ztracy_module);
    exe.linkLibrary(ztracy.artifact("tracy"));

    const options = b.addOptions();
    const messages = b.option(u32, "max_messages", "how many messages") orelse 1000;
    const use_gpa = b.option(bool, "use_gpa", "if gpa should be used as allocator") orelse false;
    options.addOption(u32, "max_messages", messages);
    options.addOption(bool, "use_gpa", use_gpa);

    exe.root_module.addImport("helper", helper);
    exe.root_module.addImport("clap", clap);
    exe.root_module.addImport("actor", actor);

    exe.root_module.addOptions("config", options);

    exe.linkLibCpp();

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/root.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}

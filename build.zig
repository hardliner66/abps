const std = @import("std");

pub const ExeConfig = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    helper: *std.Build.Module,
    clap: *std.Build.Module,
    actor: *std.Build.Module,
    use_tracy: bool,
};

pub fn add_tracy(
    exe: *std.Build.Step.Compile,
    ztracy: *std.Build.Dependency,
    ztracy_module: *std.Build.Module,
) void {
    exe.root_module.addImport("ztracy", ztracy_module);
    exe.linkLibrary(ztracy.artifact("tracy"));
}

pub fn add_fake_tracy(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const fake_tracy = b.createModule(.{
        .root_source_file = .{ .path = "modules/fake_tracy/fake_tracy.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("ztracy", fake_tracy);
}

pub fn make_exe(
    b: *std.Build,
    name: []const u8,
    main_file: []const u8,
    cfg: ExeConfig,
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = .{ .path = main_file },
        .target = cfg.target,
        .optimize = cfg.optimize,
    });

    const options = b.addOptions();
    options.addOption(bool, "use_tracy", cfg.use_tracy);

    exe.root_module.addImport("helper", cfg.helper);
    exe.root_module.addImport("clap", cfg.clap);
    exe.root_module.addImport("actor", cfg.actor);

    exe.root_module.addOptions("config", options);

    exe.linkLibCpp();

    return exe;
}

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

    const use_tracy = b.option(bool, "use_tracy", "enable tracy") orelse false;

    const use_lfqueue = b.option(bool, "use_lfqueue", "should a lfqueue be used") orelse false;

    const actor_options = b.addOptions();
    actor_options.addOption(bool, "use_lfqueue", use_lfqueue);
    actor_options.addOption(bool, "use_tracy", use_tracy);

    const clap = b.createModule(.{
        .root_source_file = .{ .path = "extern/zig-clap/clap.zig" },
        .target = target,
        .optimize = optimize,
    });

    const ztracy = b.dependency("ztracy", .{
        .enable_ztracy = use_tracy,
        .enable_fibers = false,
        .on_demand = false,
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

    if (!target.result.cpu.arch.isARM()) {
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
    }

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

    const cfg = .{
        .target = target,
        .optimize = optimize,
        .helper = helper,
        .clap = clap,
        .actor = actor,
        .use_tracy = use_tracy,
    };

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    const exe = make_exe(
        b,
        "abps",
        "src/abps.zig",
        cfg,
    );
    if (use_tracy) {
        add_tracy(exe, ztracy, ztracy_module);
    } else {
        add_fake_tracy(b, exe, target, optimize);
    }

    b.installArtifact(exe);

    const bench_mailbox_performance = make_exe(b, "bench_mailbox_performance", "bench/mailbox_performance.zig", cfg);
    if (use_tracy) {
        add_tracy(bench_mailbox_performance, ztracy, ztracy_module);
    } else {
        add_fake_tracy(b, bench_mailbox_performance, target, optimize);
    }
    b.installArtifact(bench_mailbox_performance);

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
    test_step.dependOn(&run_exe_unit_tests.step);
}

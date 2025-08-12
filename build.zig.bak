const std = @import("std");

pub const ExeConfig = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    helper: *std.Build.Module,
    clap: *std.Build.Module,
    actor: *std.Build.Module,
};

pub fn make_exe(
    b: *std.Build,
    name: []const u8,
    main_file: []const u8,
    cfg: ExeConfig,
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{ .name = name, .root_module = b.createModule(.{
        .root_source_file = b.path(main_file),
        .target = cfg.target,
        .optimize = cfg.optimize,
    }) });

    const options = b.addOptions();

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

    const use_lfqueue = b.option(bool, "use_lfqueue", "should a lfqueue be used") orelse false;

    const actor_options = b.addOptions();
    actor_options.addOption(bool, "use_lfqueue", use_lfqueue);

    const clap = b.createModule(.{
        .root_source_file = b.path("extern/zig-clap/clap.zig"),
        .target = target,
        .optimize = optimize,
    });

    const helper = b.createModule(.{
        .root_source_file = b.path("modules/helper/helper.zig"),
        .target = target,
        .optimize = optimize,
    });

    const containers = b.createModule(.{
        .root_source_file = b.path("modules/containers/containers.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (!target.result.cpu.arch.isArm()) {
        const release_flags = [_][]const u8{};
        const debug_flags = [_][]const u8{"-O3"};
        const flags = if (optimize == .Debug) &debug_flags else &release_flags;

        containers.addIncludePath(b.path("extern/concurrentqueue"));
        containers.addIncludePath(b.path("extern/concurrentqueue/c_api"));
        containers.addIncludePath(b.path("extern/concurrentqueue/internal"));
        containers.addCSourceFile(.{
            .file = b.path("extern/concurrentqueue/c_api/concurrentqueue.cpp"),
            .flags = flags,
        });
    }

    const actor = b.createModule(.{
        .root_source_file = b.path("modules/actor/actor.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (target.result.os.tag == .windows) {
        actor.addIncludePath(b.path("c/win"));
    } else {
        actor.addIncludePath(b.path("c/linux"));
    }
    actor.addImport("helper", helper);
    actor.addImport("containers", containers);
    actor.addOptions("config", actor_options);

    const cfg = ExeConfig{
        .target = target,
        .optimize = optimize,
        .helper = helper,
        .clap = clap,
        .actor = actor,
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

    b.installArtifact(exe);

    const bench_mailbox_performance = make_exe(b, "bench_mailbox_performance", "bench/mailbox_performance.zig", cfg);
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
}

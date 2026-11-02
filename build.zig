const std = @import("std");
const zine = @import("zine");
const assert = std.debug.assert;

/// Zig projects with autodoc pages at `/docs/<name>/`, from the checkout given
/// by `-D<name>=<path>`, else `default` (relative to www) if it exists.
/// `root` is relative to the checkout.
const doc_projects = [_]struct { name: []const u8, root: []const u8, default: []const u8 }{
    .{ .name = "rstd", .root = "src/__root__.zig", .default = "../vendor/rgui/vendor/rstd" },
};

pub fn build(b: *std.Build) !void {
    var build_assets: std.ArrayList(zine.BuildAsset) = .empty;
    try addDocs(b, &build_assets);

    // Built from source, zine reports a "-dev" version that zine.ziggy rejects.
    const zine_exe: @FieldType(zine.Options, "zine") = .{ .path = try localZine(b) };

    const website = zine.website(b, .{
        .build_assets = build_assets.items,
        .force = true,
        .zine = zine_exe,
    });
    b.getInstallStep().dependOn(&website.step);

    const serve = zine.serve(b, .{
        .build_assets = build_assets.items,
        .zine = zine_exe,
    });
    serve.addPassthruArgs();
    b.step("serve", "serve the zine website").dependOn(&serve.step);
}

/// Autodoc output is a generic viewer (from an empty stub, so the projects
/// themselves never compile here) plus each project's packed sources.
fn addDocs(b: *std.Build, assets: *std.ArrayList(zine.BuildAsset)) !void {
    var viewer: ?std.Build.LazyPath = null;
    var docs_tar: ?*std.Build.Step.Compile = null;

    for (doc_projects) |project| {
        const checkout: std.Build.LazyPath = if (b.option(
            []const u8,
            project.name,
            b.fmt("Checkout of {s} to generate API docs from (default: {s})", .{ project.name, project.default }),
        )) |path| .{ .cwd_relative = path } else if (defaultExists(b, project.default)) b.path(project.default) else continue;

        viewer = viewer orelse b.addObject(.{
            .name = "docs-viewer",
            .root_module = b.createModule(.{
                .root_source_file = b.addWriteFiles().add("viewer.zig", ""),
                .target = b.graph.host,
            }),
        }).getEmittedDocs();
        docs_tar = docs_tar orelse b.addExecutable(.{
            .name = "docs_tar",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tools/docs_tar.zig"),
                .target = b.graph.host,
            }),
        });

        const pack = b.addRunArtifact(docs_tar.?);
        // Reads a whole source tree the cache can't see.
        pack.has_side_effects = true;
        const sources = pack.addOutputFileArg("sources.tar");
        pack.addArg(project.name);
        pack.addFileArg(checkout.path(b, project.root));

        for ([_][]const u8{ "index.html", "main.js", "main.wasm", "sources.tar" }) |file| {
            try assets.append(b.allocator, .{
                .name = b.fmt("docs-{s}-{s}", .{ project.name, file }),
                .lp = if (std.mem.eql(u8, file, "sources.tar")) sources else viewer.?.path(b, file),
                .install_path = b.fmt("docs/{s}/{s}", .{ project.name, file }),
                .install_always = true,
            });
        }
    }
}

/// Configure is cached, so watch the nearest existing ancestor for the
/// checkout coming or going.
fn defaultExists(b: *std.Build, default: []const u8) bool {
    var watch = std.fs.path.dirname(default) orelse ".";
    while (true) : (watch = std.fs.path.dirname(watch) orelse ".") {
        b.root.access(b.graph.io, watch, .{}) catch continue;
        break;
    }
    b.dependOnDirectoryMetadata(b.path(watch));
    b.root.access(b.graph.io, default, .{}) catch return false;
    return true;
}

/// www's own release binary if present, else null for `zine` on PATH (CI).
fn localZine(b: *std.Build) !?[]const u8 {
    const name = b.fmt("zine{s}", .{b.graph.host.result.exeFileExt()});
    b.dependOnDirectoryMetadata(b.path("."));
    // setup-zine leaves a `zine/` directory here in CI.
    const stat = b.root.statFile(b.graph.io, name) catch return null;
    if (stat.kind != .file) return null;
    return try b.root.joinString(b.graph.arena, name);
}

fn installFile(b: *std.Build, lp: std.Build.LazyPath, dest_rel_path: []const u8) void {
    b.getInstallStep().dependOn(&b.addInstallFile(lp, dest_rel_path).step);
}

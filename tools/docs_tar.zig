//! Packs a module's sources into an autodoc `sources.tar` without compiling
//! it, using the same file selection as the compiler's `-femit-docs`.
//! Usage: docs_tar <out.tar> <module name> <root file>
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 4) std.process.fatal("usage: {s} <out.tar> <module name> <root file>", .{args[0]});
    const out_path, const name, const root_path = args[1..4].*;
    const root_name = std.fs.path.basename(root_path);

    var src_dir = try std.Io.Dir.cwd().openDir(io, std.fs.path.dirname(root_path) orelse ".", .{ .iterate = true });
    defer src_dir.close(io);

    var paths: std.ArrayList([]const u8) = .empty;
    var walker = try src_dir.walk(arena);
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
        if (std.mem.eql(u8, entry.basename, "test.zig") or std.mem.endsWith(u8, entry.basename, "_test.zig")) continue;
        const path = try arena.dupe(u8, entry.path);
        std.mem.replaceScalar(u8, path, std.fs.path.sep, '/');
        if (!std.mem.eql(u8, path, root_name)) try paths.append(arena, path);
    }
    // Autodoc takes a module's first file as its root; sorted rest keeps output reproducible.
    std.mem.sort([]const u8, paths.items, {}, lessThan);
    try paths.insert(arena, 0, root_name);

    var out_file = try std.Io.Dir.cwd().createFile(io, out_path, .{});
    defer out_file.close(io);
    var buf: [64 * 1024]u8 = undefined;
    var out = out_file.writer(io, &buf);
    var tar: std.tar.Writer = .{ .underlying_writer = &out.interface, .prefix = name };
    for (paths.items) |path| {
        const bytes = try src_dir.readFileAlloc(io, path, gpa, .unlimited);
        defer gpa.free(bytes);
        try tar.writeFileBytes(path, bytes, .{});
    }
    try out.end();
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

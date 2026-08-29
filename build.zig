const std = @import("std");
const zine = @import("zine");
const assert = std.debug.assert;

pub fn build(b: *std.Build) void {
    // var build_assets = std.array_list.Managed(zine.BuildAsset).init(b.allocator);

    const website = zine.website(b, .{
        // .build_assets = build_assets.items,
        .force = true,
    });
    b.getInstallStep().dependOn(&website.step);

    const serve = zine.serve(b, .{
        // .build_assets = build_assets.items
    });
    b.step("serve", "serve the zine website").dependOn(&serve.step);
}

fn installFile(b: *std.Build, lp: std.Build.LazyPath, dest_rel_path: []const u8) void {
    b.getInstallStep().dependOn(&b.addInstallFile(lp, dest_rel_path).step);
}

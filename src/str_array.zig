const std = @import("std");
const raw = @import("internal/raw.zig");
const internal = @import("internal/internal.zig");
const log = std.log.scoped(.git);

const git = @import("git.zig");

pub const StrArray = extern struct {
    strings: [*c][*c]u8 = null,
    count: usize = 0,

    pub fn fromSlice(slice: []const [*:0]const u8) StrArray {
        return .{
            .strings = @intToPtr([*c][*c]u8, @ptrToInt(slice.ptr)),
            .count = slice.len,
        };
    }

    pub fn toSlice(self: StrArray) []const [*:0]const u8 {
        if (self.count == 0) return &[_][*:0]const u8{};
        return @ptrCast([*]const [*:0]const u8, self.strings)[0..self.count];
    }

    /// This should be called only on `StrArray`'s provided by the library
    pub fn deinit(self: *StrArray) void {
        log.debug("StrArray.deinit called", .{});

        raw.git_strarray_dispose(internal.toC(self));

        log.debug("StrArray freed successfully", .{});
    }

    pub fn copy(self: StrArray) !StrArray {
        log.debug("StrArray.copy called", .{});

        var result: StrArray = undefined;
        try internal.wrapCall("git_strarray_copy", .{ internal.toC(&result), internal.toC(&self) });

        log.debug("StrArray copied successfully", .{});

        return result;
    }

    test {
        try std.testing.expectEqual(@sizeOf(raw.git_strarray), @sizeOf(StrArray));
        try std.testing.expectEqual(@bitSizeOf(raw.git_strarray), @bitSizeOf(StrArray));
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

comptime {
    std.testing.refAllDecls(@This());
}

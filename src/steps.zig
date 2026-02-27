const std = @import("std");

fn steps1(num: u64) u64 {
    var n: u64 = 0;
    var a: u64 = num;
    while (a != 0) {
        a = if (a & 1 == 0) a / 2 else a - 1;
        n += 1;
    }
    return n;
}

fn steps2(num: u64) u64 {
    return @popCount(num) + 63 - @clz(num);
}

fn expect(steps: fn (num: u64) u64) !void {
    try std.testing.expectEqual(5, steps(10));
    try std.testing.expectEqual(6, steps(11));
    try std.testing.expectEqual(5, steps(12));
    try std.testing.expectEqual(16, steps(2633));
}

test "steps 1" {
    try expect(steps1);
}
test "steps 2" {
    try expect(steps2);
}

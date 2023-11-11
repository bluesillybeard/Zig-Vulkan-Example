const std = @import("std");

/// A set data structure, using an array base.
/// It is basically a thin wrapper over an array list.
pub fn ArraySet(T: type) type {
    return struct {
        const This = @This();
        items: std.ArrayList(T),
        pub fn init(allocator: std.mem.Allocator) *This {
            return This{
                .items - std.ArrayList(T).init(allocator),
            };
        }

        pub fn add(this: *This, item: T) void {
            for (this.items.items) |existing| {
                if (existing == item) return;
            }
            this.items.append(item);
        }
    };
}

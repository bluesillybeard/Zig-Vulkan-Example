// This just imports cglm (it's a header library) so its functions aren't inlined and duplicated all over the place
// TODO: make a zig wrapper so its more ergonomic to use
pub const cglm = @cImport(@cInclude("cglm/cglm.h"));

pub const libnix = @cImport({
    @cInclude("nix_api_util.h");
    @cInclude("nix_api_expr.h");
    @cInclude("nix_api_store.h");
    @cInclude("nix_api_value.h");
});

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        omnisharp = false,
        csharp_ls = {
          cmd = {
            "csharp-ls",
            "--solution",
            "MultiTenantSaasPlatform.sln",
          },
          setup = {
            csharp_ls = function(server, opts)
              require("lspconfig")[server].setup(opts)
            end,
          },
        },
      },
    },
  },
}

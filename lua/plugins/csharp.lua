return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        roslyn_ls = {
          mason = false,
        },
        csharp_ls = false,
        omnisharp = false,
      },
    },
  },
}

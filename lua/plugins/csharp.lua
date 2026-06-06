return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        omnisharp = false,
        csharp_ls = false,
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    config = function()
      local lspconfig = require("lspconfig")

      lspconfig.util.on_setup = nil

      vim.lsp.config("roslyn_ls", {
        default_config = {
          cmd = {
            "roslyn-language-server",
            "--logLevel",
            "Information",
          },
          filetypes = { "cs" },
          root_dir = function(fname)
            return lspconfig.util.root_pattern("*.sln", "*.slnx", "*.csproj")(fname)
          end,
          init_options = {
            enableInlineDiagnostics = true,
          },
          settings = {
            ["csharp"] = {
              inlayHints = {
                enable = true,
              },
              suggest = {
                includeSymbolsFromUnimportedNamespaces = true,
              },
            },
          },
        },
      })

      vim.lsp.enable("roslyn_ls")
    end,
  },
}

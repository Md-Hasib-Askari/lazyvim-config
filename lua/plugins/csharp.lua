return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts = opts or {}
      opts.servers = vim.tbl_deep_extend("force", opts.servers or {}, {
        omnisharp = false,
        csharp_ls = false,
      })
    end,
    init = function()
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "cs",
        group = vim.api.nvim_create_augroup("roslyn_ls_start", { clear = true }),
        callback = function(args)
          local clients = vim.lsp.get_clients({ name = "roslyn_ls", bufnr = args.buf })
          if #clients > 0 then
            return
          end
          local root_dir = require("lspconfig.util").root_pattern(
            "*.sln", "*.slnx", "*.csproj"
          )(args.buf)
          if root_dir then
            vim.lsp.start({
              name = "roslyn_ls",
              cmd = { "roslyn-language-server", "--logLevel", "Information" },
              root_dir = root_dir,
              filetypes = { "cs" },
              init_options = { enableInlineDiagnostics = true },
              settings = {
                csharp = {
                  inlayHints = { enable = true },
                  suggest = { includeSymbolsFromUnimportedNamespaces = true },
                },
              },
            })
          end
        end,
      })
    end,
  },
}

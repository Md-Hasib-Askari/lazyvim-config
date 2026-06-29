return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        vtsls = {
          enabled = true,
          filetypes = {
            "javascript",
            "javascriptreact",
            "javascript.jsx",
            "typescript",
            "typescriptreact",
            "typescript.tsx",
          },
          root_dir = function(bufnr, callback)
            local fname = vim.api.nvim_buf_get_name(bufnr)
            local util = require("lspconfig.util")
            local root = util.root_pattern("tsconfig.json", "package.json", "jsconfig.json")(fname)
            if root then
              callback(root)
            end
          end,
          settings = {
            vtsls = {
              autoUseWorkspaceTsdk = true,
            },
          },
        },
      },
    },
  },
}

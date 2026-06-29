-- Restore LazyVim-style inline diagnostic virtual text
vim.diagnostic.config({
  underline = true,
  update_in_insert = false,
  virtual_text = {
    spacing = 4,
    source = "if_many",
    prefix = "●",
  },
  virtual_lines = false,
  severity_sort = true,
  signs = true,
})

vim.g.root_spec = {
  { "package.json" },
  { "tsconfig.json" },
  { "jsconfig.json" },
  { ".git" },
  { ".null-ls-root" },
  { "Makefile" },
  { "package-lock.json" },
  { "pnpm-lock.yaml" },
  { "yarn.lock" },
  "lsp",
  "cwd",
}

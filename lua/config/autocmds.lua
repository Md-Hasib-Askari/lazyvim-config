-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Auto-show diagnostics in a float when the cursor rests on a line (your
-- previous vanilla behavior). updatetime governs the delay; LazyVim sets 200ms.
vim.api.nvim_create_autocmd("CursorHold", {
  group = vim.api.nvim_create_augroup("user_diagnostic_float", { clear = true }),
  callback = function()
    vim.diagnostic.open_float(nil, { focusable = false })
  end,
})

-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- NOTE: number, relativenumber, tabstop/shiftwidth=2, expandtab, ignorecase,
-- smartcase, clipboard=unnamedplus, mouse, signcolumn=yes are all already
-- LazyVim defaults, so they're omitted here.

-- Indent-based folding (your previous vanilla behavior). LazyVim defaults to
-- treesitter foldexpr; override it back to indent + everything unfolded.
vim.opt.foldmethod = "indent"
vim.opt.foldexpr = ""
vim.opt.foldlevel = 99
vim.opt.foldenable = true

-- Disable unused providers to suppress healthcheck warnings
vim.g.loaded_python3_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_node_provider = 0 -- copilot.lua spawns node directly; no need for the neovim npm package

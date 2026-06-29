-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Re-trigger LSP attach for TypeScript/React buffers on VeryLazy so vtsls
-- attaches even when the buffer was already open before the LSP plugin loaded.
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  once = true,
  callback = function()
    local ts_fts = {
      typescript = true,
      typescriptreact = true,
      javascript = true,
      javascriptreact = true,
    }
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) and ts_fts[vim.bo[buf].filetype] then
        vim.api.nvim_exec_autocmds("FileType", { buffer = buf })
      end
    end
  end,
})

-- Auto-show diagnostics in a float when the cursor rests on a line (your
-- previous vanilla behavior). updatetime governs the delay; LazyVim sets 200ms.
vim.api.nvim_create_autocmd("CursorHold", {
  group = vim.api.nvim_create_augroup("user_diagnostic_float", { clear = true }),
  callback = function()
    vim.diagnostic.open_float(nil, { focusable = false })
  end,
})
-- Create missing parent directories when saving a file, so writing a brand-new
-- path (e.g. an agent.lua multi-file apply that scaffolds src/Foo/Bar/Baz.cs)
-- just works instead of failing with "no such file or directory".
vim.api.nvim_create_autocmd("BufWritePre", {
  group = vim.api.nvim_create_augroup("user_mkdir_on_save", { clear = true }),
  callback = function(args)
    -- Skip protocol buffers (oil://, fugitive://, ...) and non-file buffers.
    if args.match:match("^%w%w+://") or vim.bo[args.buf].buftype ~= "" then
      return
    end
    local dir = vim.fn.fnamemodify(args.match, ":p:h")
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, "p")
    end
  end,
})
-- Auto-save buffers when text changes (e.g. after accepting a tool-applied
-- diff) or when leaving Insert mode. Uses `update` so it only writes if the
-- buffer is actually modified. Skips special buffers and unnamed buffers.
vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave" }, {
  group = vim.api.nvim_create_augroup("user_auto_save", { clear = true }),
  callback = function(args)
    local buf = args.buf
    if vim.bo[buf].buftype ~= "" or not vim.bo[buf].modifiable then
      return
    end
    vim.cmd("silent! update")
  end,
})

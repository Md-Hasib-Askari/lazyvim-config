-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local map = vim.keymap.set

-- Only keymaps with no LazyVim equivalent live here. The rest use LazyVim's
-- defaults: save=<C-s>, quit=<leader>qq, grep=<leader>sg or <leader>/,
-- buffers=<leader>,, help=<leader>sh, and <Esc> already clears search highlight.

-- Yank the diagnostic message under the cursor to the system clipboard.
map("n", "<leader>y", function()
  local diag = vim.diagnostic.get(0, { lnum = vim.fn.line(".") - 1 })[1]
  if diag then
    vim.fn.setreg("+", diag.message)
    vim.notify("Copied: " .. diag.message)
  end
end, { desc = "Yank diagnostic message" })

-- Claude Code: open in a right-hand tmux split and send the current file.
map("n", "<leader>cc", function()
  local file = vim.fn.expand("%:p")
  vim.fn.system("tmux split-window -h -l 30% 'claude'")
  if file ~= "" then
    vim.defer_fn(function()
      vim.fn.system(string.format("tmux send-keys '@%s' ''", file))
    end, 1500)
  end
end, { desc = "Open Claude with current file" })

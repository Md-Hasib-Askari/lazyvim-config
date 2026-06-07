-- Docker container/image UI via lazydocker in a floating terminal.
-- Prerequisite: install lazydocker (https://github.com/jesseduffield/lazydocker).
--
-- Keymaps (leader = <space>):
--   <leader>dc    open lazydocker in a floating terminal
--   <leader>dps   fallback: docker ps in a horizontal split (if lazydocker missing)

return {
  {
    "nvim-telescope/telescope.nvim",
    keys = {
      {
        "<leader>dc",
        function()
          -- Check if lazydocker is available
          if vim.fn.executable("lazydocker") == 1 then
            local buf = vim.api.nvim_create_buf(false, true)
            local width = math.floor(vim.o.columns * 0.9)
            local height = math.floor(vim.o.lines * 0.9)
            local row = math.floor((vim.o.lines - height) / 2)
            local col = math.floor((vim.o.columns - width) / 2)
            local win = vim.api.nvim_open_win(buf, true, {
              relative = "editor",
              width = width,
              height = height,
              row = row,
              col = col,
              border = "rounded",
              title = " lazydocker ",
              title_pos = "center",
            })
            vim.fn.termopen("lazydocker")
            vim.cmd("startinsert")
            -- Close on <Esc> or q
            vim.api.nvim_buf_set_keymap(buf, "t", "<Esc>", "<C-\\><C-n>:q<CR>", { noremap = true, silent = true })
            vim.api.nvim_buf_set_keymap(buf, "t", "q", "<C-\\><C-n>:q<CR>", { noremap = true, silent = true })
          else
            vim.notify(
              "lazydocker not found. Install it: https://github.com/jesseduffield/lazydocker",
              vim.log.levels.WARN
            )
            -- Fallback: plain docker ps in a split
            vim.cmd(
              "split | terminal docker ps --format 'table {{.ID}}\t{{.Image}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}'"
            )
          end
        end,
        desc = "Docker UI (lazydocker)",
      },
    },
  },
}

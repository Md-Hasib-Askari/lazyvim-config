return {
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    -- The clock lives in the tmux status bar already, so drop lualine's.
    opts.sections.lualine_z = {}
  end,
}

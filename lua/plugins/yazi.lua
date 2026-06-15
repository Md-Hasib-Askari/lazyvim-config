-- Yazi as the primary file manager on <leader>e / <leader>E (your habit),
-- while keeping LazyVim's neo-tree available on <leader>fe / <leader>fE.
return {
  {
    "mikavilpas/yazi.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>e", "<cmd>Yazi<cr>", desc = "Yazi (current file)" },
      { "<leader>E", "<cmd>Yazi cwd<cr>", desc = "Yazi (cwd)" },
    },
    opts = {
      open_for_directories = true,
    },
  },

  -- Disable neo-tree's claim on <leader>e / <leader>E so yazi wins those keys.
  -- neo-tree stays reachable via LazyVim's <leader>fe / <leader>fE.
  {
    "nvim-neo-tree/neo-tree.nvim",
    keys = {
      { "<leader>e", false },
      { "<leader>E", false },
    },
  },
  -- Also disable Snacks explorer's <leader>e / <leader>E remaps
  {
    "folke/snacks.nvim",
    keys = {
      { "<leader>e", false },
      { "<leader>E", false },
    },
  },
}

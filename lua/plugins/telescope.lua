-- The telescope extra (enabled in lazyvim.json) provides find files, grep,
-- buffers, help, etc. via LazyVim's own keymaps. The ONLY thing missing in the
-- LazyVim way is the file_browser extension, so that's all we add here.
return {
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      {
        "nvim-telescope/telescope-file-browser.nvim",
        config = function()
          require("telescope").load_extension("file_browser")
        end,
      },
    },
    keys = {
      -- <leader>fb is LazyVim's "buffers"; file_browser lives on a free slot.
      { "<leader>fd", "<cmd>Telescope file_browser<cr>", desc = "File Browser" },
    },
  },
}

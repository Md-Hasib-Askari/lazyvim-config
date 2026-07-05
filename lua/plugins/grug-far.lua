return {
  {
    "MagicDuck/grug-far.nvim",
    keys = {
      {
        "<leader>sr",
        function()
          local grug = require("grug-far")
          local path = vim.api.nvim_buf_get_name(0)
          grug.open({
            transient = true,
            prefills = {
              paths = path ~= "" and path or nil,
            },
          })
        end,
        mode = { "n", "x" },
        desc = "Search and Replace in current buffer",
      },
    },
  },
}

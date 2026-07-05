return {
  {
    "mistweaverco/kulala.nvim",
    keys = {
      { "<leader>Rs", desc = "Send request" },
      { "<leader>Ra", desc = "Send all requests" },
      { "<leader>Rb", desc = "Open scratchpad" },
    },
    opts = {
      global_keymaps = {
        ["Jump to next request"] = { "N", function() require("kulala").jump_next() end, ft = { "http", "rest" } },
        ["Jump to previous request"] = { "P", function() require("kulala").jump_prev() end, ft = { "http", "rest" } },
        ["Close window"] = { "Q", function() require("kulala").close() end, ft = { "http", "rest" } },
        ["Toggle headers/body"] = { "T", function() require("kulala").toggle_view() end, ft = { "http", "rest" } },
        ["Clear globals"] = { "d", function() require("kulala").scripts_clear_global() end, ft = { "http", "rest" } },
        ["Clear cached files"] = { "D", function() require("kulala").clear_cached_files() end, ft = { "http", "rest" } },
      },
      ui = {
        display_mode = "split",
        split_direction = "right",
      },
    },
  },
}

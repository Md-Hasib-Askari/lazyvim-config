return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    config = function(_, opts)
      -- 1. Event handlers: Snacks rename + force dotfiles on every render
      local events = require("neo-tree.events")
      local manager = require("neo-tree.sources.manager")
      opts.event_handlers = opts.event_handlers or {}
      vim.list_extend(opts.event_handlers, {
        -- LazyVim's original handlers
        {
          event = events.FILE_MOVED,
          handler = function(data)
            Snacks.rename.on_rename_file(data.source, data.destination)
          end,
        },
        {
          event = events.FILE_RENAMED,
          handler = function(data)
            Snacks.rename.on_rename_file(data.source, data.destination)
          end,
        },
        -- Force filtered_items right before every render (catches all sources)
        {
          event = "before_render",
          handler = function(state)
            if state.filtered_items then
              state.filtered_items.hide_dotfiles = false
              state.filtered_items.hide_gitignored = false
              state.filtered_items.visible = true
            end
          end,
        },
        -- Debug notification to confirm the patch is applied
        {
          event = events.NEO_TREE_WINDOW_AFTER_OPEN,
          handler = function()
            local state = manager.get_state("filesystem")
            if state then
              vim.notify("neo-tree: hide_dotfiles="
                .. tostring(state.filtered_items and state.filtered_items.hide_dotfiles)
                .. " visible="
                .. tostring(state.filtered_items and state.filtered_items.visible))
            end
          end,
        },
      })

      -- 2. Call neo-tree's setup
      require("neo-tree").setup(opts)

      -- 3. Patch global config
      local config = require("neo-tree").ensure_config()
      if config.filesystem then
        config.filesystem.filtered_items = config.filesystem.filtered_items or {}
        config.filesystem.filtered_items.hide_dotfiles = false
        config.filesystem.filtered_items.hide_gitignored = false
        config.filesystem.filtered_items.visible = true
      end
    end,
    opts = {
      filesystem = {
        filtered_items = {
          hide_dotfiles = false,
          hide_gitignored = false,
          visible = true,
        },
      },
    },
  },
}

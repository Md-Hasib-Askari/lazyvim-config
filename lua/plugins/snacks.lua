return {
  {
    "folke/snacks.nvim",
    opts = {
      image = { enabled = false }, -- tmux doesn't support kitty graphics protocol
      dashboard = {
        sections = {
          {
            section = "header",
          },
          {
            section = "terminal",
            cmd = "echo ' ' && echo '  ' $(basename $(git rev-parse --show-toplevel 2>/dev/null || pwd)) && echo '  ' $(git rev-parse --show-toplevel 2>/dev/null || pwd)",
            height = 3,
            padding = 1,
            ttl = 0,
          },
          { section = "keys", gap = 1, padding = 1 },
          {
            section = "recent_files",
            cwd = true,
            title = "Recent Files",
            padding = 1,
          },
          {
            section = "projects",
            title = "Projects",
            padding = 1,
          },
          { section = "startup" },
        },
      },
    },
  },
}

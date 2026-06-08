# Project Overview
Personal Neovim configuration built on [LazyVim](https://github.com/LazyVim/LazyVim), using Lua as the primary language. It extends the LazyVim framework with a curated set of plugins and custom mappings (C#, tmux navigation, Yazi file manager, markdown preview, etc.) while keeping everything else LazyVim-idiomatic. Plugin versions are pinned (`lazy-lock.json`) and enabled extras tracked (`lazyvim.json`) for reproducible setups.

# Architecture
The entry point is `init.lua`, which bootstraps `lazy.nvim` through `lua/config/lazy.lua`. Plugin specifications live individually under `lua/plugins/` (each file defines one or more related plugins) and are loaded by the lazy.nvim plugin manager. Core Neovim options, keymaps, and autocmds are configured in `lua/config/options.lua`, `lua/config/keymaps.lua`, and `lua/config/autocmds.lua`. A custom Lua module `lua/agent.lua` provides additional utilities (e.g., opening Claude in a tmux split). LazyVim extras (e.g., `lang.dotnet`) are declared in `lazyvim.json`. Code formatting rules are defined in `stylua.toml`.

# Build / Test / Run
There are no build steps. The only command is to launch Neovim:

```sh
nvim
```

On first run, `lazy.nvim` installs all plugins and `mason.nvim` automatically installs configured LSP servers and formatters. A C compiler (`gcc`/`cc`) is needed for Treesitter parsers, and external tools (`ripgrep`, `fd`, `fzf`, `lazygit`, `yazi`, Node.js, .NET SDK) are required by specific plugins (see README). No test suite is present.

# Conventions
- **Formatting**: 2-space indentation, max line width 120 columns (`stylua.toml`).
- **File organisation**: Plugin specs go in `lua/plugins/<name>.lua`, core config in `lua/config/<type>.lua`, and custom helper modules directly in `lua/` (e.g., `agent.lua`).
- **Naming**: Lua files are lowercase with hyphens where needed; LazyVim extras are referenced in `lazyvim.json`.
- **Keymaps**: Leader key defaults to `<space>`; custom mappings are defined in `lua/config/keymaps.lua` using the `vim.keymap.set` pattern (e.g., `<leader>e` for Yazi, `<leader>fd` for telescope file browser, `<C-h/j/k/l>` for tmux navigation).
- **Plugin management**: Lazy.nvim with pinned versions in `lazy-lock.json`; all plugin specs follow the lazy.nvim spec style.
- **Idiom**: Favour LazyVim defaults; only override or add what is not provided.

# Key Directories
- `lua/config/` — Core Neovim settings: options, keymaps, autocmds, and lazy.nvim bootstrap.
- `lua/plugins/` — Individual lazy.nvim plugin specifications (C#, telescope, yazi, etc.).
- `lua/` — Custom Lua modules (`agent.lua`).
- `.` (root) — Entry point `init.lua`, lock files (`lazy-lock.json`, `lazyvim.json`), and project configuration (`stylua.toml`, `README.md`).

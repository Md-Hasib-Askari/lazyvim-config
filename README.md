# 💤 Neovim config (LazyVim-based)

My personal Neovim setup, built on [LazyVim](https://github.com/LazyVim/LazyVim).
The philosophy: **use the LazyVim-idiomatic way wherever LazyVim provides it, and
only add custom plugins for the genuine gaps.** Plugin versions are pinned in
`lazy-lock.json` and enabled extras are tracked in `lazyvim.json`, so a clone
reproduces the exact same environment.

## Requirements

| Tool | Why | Install (Ubuntu/Debian) |
|------|-----|--------------------------|
| Neovim **≥ 0.11** | base | from neovim.io / your package manager |
| A **Nerd Font** | icons | https://www.nerdfonts.com (set it in your terminal) |
| `git` | plugin manager | `sudo apt install git` |
| `ripgrep` (`rg`) | telescope live grep | `sudo apt install ripgrep` |
| `fd` | telescope file finding | `sudo apt install fd-find` (binary is `fdfind`; symlink to `fd`) |
| `fzf` | fuzzy matching | `sudo apt install fzf` |
| `lazygit` | git UI (`<leader>gg`) | https://github.com/jesseduffield/lazygit |
| `yazi` | file manager (`<leader>e`) | https://github.com/sxyazi/yazi |
| A C compiler (`gcc`/`cc`) | treesitter parsers | `sudo apt install build-essential` |
| Node.js | Copilot, markdown-preview | https://nodejs.org / nvm |
| .NET SDK (`dotnet`) | C# (omnisharp) | https://dotnet.microsoft.com |
| `brave-browser` | markdown preview window | optional; edit the opener in `lua/plugins/markdown-preview.lua` to use another browser |

LSP servers and formatters (omnisharp, csharpier, etc.) are installed
automatically by **Mason** on first launch — no manual step needed.

## Install

```sh
# Back up any existing config first
mv ~/.config/nvim{,.bak}
mv ~/.local/share/nvim{,.bak}
mv ~/.local/state/nvim{,.bak}
mv ~/.cache/nvim{,.bak}

# Clone this repo
git clone <THIS_REPO_URL> ~/.config/nvim

# Launch — lazy.nvim + Mason bootstrap everything on first run
nvim
```

On first launch, let Mason finish installing servers/formatters. C# (omnisharp)
takes ~1 minute to load a project the first time.

## What's customized (the gaps LazyVim doesn't fill)

| Feature | Plugin | Key |
|---------|--------|-----|
| File manager | `yazi.nvim` | `<leader>e` / `<leader>E` (neo-tree kept on `<leader>fe`) |
| Telescope file browser | `telescope-file-browser.nvim` | `<leader>fd` |
| Markdown preview | `markdown-preview.nvim` | `<leader>cm` |
| tmux ⇄ nvim navigation | `vim-tmux-navigator` | `<C-h/j/k/l>` (needs matching tmux config) |
| Open Claude in a tmux split | custom keymap | `<leader>cc` |
| Yank diagnostic message | custom keymap | `<leader>y` |
| Indent-based folding | option override | — |
| Diagnostic float on hover | autocmd | (automatic) |

Everything else (completion via blink.cmp, C# via the `lang.dotnet` extra,
pickers, lazygit, formatting, comments, terminal, and core keymaps) uses
LazyVim's defaults. Enabled extras are listed in `lazyvim.json`.

> **Note:** the tmux side of `vim-tmux-navigator` lives in `~/.tmux.conf`, which
> is **not** part of this repo.

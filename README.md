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
| A **Nerd Font** | icons | <https://www.nerdfonts.com> (set it in your terminal) |
| `git` | plugin manager | `sudo apt install git` |
| `ripgrep` (`rg`) | telescope live grep | `sudo apt install ripgrep` |
| `fd` | telescope file finding | `sudo apt install fd-find` (binary is `fdfind`; symlink to `fd`) |
| `fzf` | fuzzy matching | `sudo apt install fzf` |
| `lazygit` | git UI (`<leader>gg`) | <https://github.com/jesseduffield/lazygit> |
| `yazi` | file manager (`<leader>e`) | <https://github.com/sxyazi/yazi> |
| A C compiler (`gcc`/`cc`) | treesitter parsers | `sudo apt install build-essential` |
| Node.js | Copilot, markdown-preview | <https://nodejs.org> / nvm |
| .NET SDK (`dotnet`) | C# (omnisharp) | <https://dotnet.microsoft.com> |
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
| Auto-save on change | autocmd | (automatic) |

Everything else (completion via blink.cmp, C# via the `lang.dotnet` extra,
pickers, lazygit, formatting, comments, terminal, and core keymaps) uses
LazyVim's defaults. Enabled extras are listed in `lazyvim.json`.

> **Note:** the tmux side of `vim-tmux-navigator` lives in `~/.tmux.conf`, which
> is **not** part of this repo.

## Clipboard-based LLM Agent

A built-in coding agent (`lua/agent.lua`) that turns any LLM chat into a
Neovim coding assistant via the clipboard. You copy prompts out, paste LLM
replies back, and Neovim applies the changes with a diff preview.

### Typical workflow

1. **`<leader>ai`** — Initialize: copies the system prompt (tool protocol +
   project context from `AGENT.md`) to the clipboard. Paste it into your LLM.
2. Ask your question. The LLM replies with a `<tool>` block.
3. **`<leader>aa`** — Apply: reads the clipboard, runs tool calls or applies
   diffs with a colored preview. Accept (`ga`/`Enter`) or reject (`q`/`Esc`).
4. The results are copied back to your clipboard — paste them into the LLM.
5. Repeat until done.

### Tool protocol

All context gathering and file changes go through `<tool>…</tool>` blocks:

```xml
<tool>
read_file src/main.py:1-30
grep "TODO"
find_file config.py
</tool>
```

**Writing files** — use `write_file` for new files or complete rewrites:

```xml
<tool>
write_file src/utils.py

```python
def hello():
    print("Hello, world!")
```

</tool>
```

**Patching files** — use `patch_file` for modifying existing files (preferred):

```xml
<tool>
patch_file src/main.py

```diff
@@ -1,5 +1,5 @@
 def greet():
-    print("Hello")
+    print("Hello, world!")
```

</tool>
```

### Available tools

| Tool | Description |
|------|-------------|
| `find_file <name>` | Locate a tracked file by name |
| `read_file <path>[:a-b]` | Read a file (optional line range) |
| `diagnostics [<path>]` | Get LSP diagnostics (workspace or single file) |
| `bash <command>` | Run a bash command (user confirms first) |
| `list_dir [<path>]` | List tracked files |
| `grep <pattern>` | Search the repo |
| `git_diff` | Show current unstaged changes |
| `write_file <path>` | Create or replace a file (full content) |
| `patch_file <path>` | Apply a unified diff to an existing file |

### Keymaps

| Key | Action |
|-----|--------|
| `<leader>ai` | Initialize: copy system prompt to clipboard |
| `<leader>aI` | Document repo → `AGENT.md` (like `/init`) |
| `<leader>aW` | Write clipboard markdown into `AGENT.md` buffer |
| `<leader>ap` | Plan: goal + context → step-by-step plan |
| `<leader>ax` | Context: ~20 lines around cursor |
| `<leader>af` | Fix: error message + file context |
| `<leader>ar` | Refactor selection (full replacement) |
| `<leader>ao` | Modify selection (full replacement) |
| `<leader>ad` | Diff selection |
| `<leader>aa` | Apply / run tools from clipboard |

### Auto-save

Buffers are automatically saved after accepting a tool-applied diff
(`TextChanged` / `InsertLeave` autocmd). You don't need to manually `:w`
after accepting changes.

### AGENT.md

If an `AGENT.md` file exists at the repo root, its contents are automatically
included as project context in the system prompt. Use `<leader>aI` to generate
one from the repo structure, then `<leader>aW` to write the LLM's reply into
the file.

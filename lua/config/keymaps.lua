-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local map = vim.keymap.set

-- Only keymaps with no LazyVim equivalent live here. The rest use LazyVim's
-- defaults: save=<C-s>, quit=<leader>qq, grep=<leader>sg or <leader>/,
-- buffers=<leader>,, help=<leader>sh, and <Esc> already clears search highlight.

-- Yank the diagnostic message under the cursor to the system clipboard.
map("n", "<leader>y", function()
  local diag = vim.diagnostic.get(0, { lnum = vim.fn.line(".") - 1 })[1]
  if diag then
    vim.fn.setreg("+", diag.message)
    vim.notify("Copied: " .. diag.message)
  end
end, { desc = "Yank diagnostic message" })

-- Claude Code: open in a right-hand tmux split and send the current file.
map("n", "<leader>cc", function()
  local file = vim.fn.expand("%:p")
  vim.fn.system("tmux split-window -h -l 30% 'claude'")
  if file ~= "" then
    vim.defer_fn(function()
      vim.fn.system(string.format("tmux send-keys '@%s' ''", file))
    end, 1500)
  end
end, { desc = "Open Claude with current file" })

-- ======================================================
-- AGENT CHEATSHEET  (clipboard-based LLM coding agent; leader = space)
-- ------------------------------------------------------
-- Typical loop:
--   <leader>ai  set up the chat (copies the system prompt) -> paste into LLM
--   ask your question; if it needs files it replies with a ```tool block
--   <leader>at  run that block -> copies TOOL RESULTS -> paste back to LLM
--   LLM replies with a diff or full file
--   <leader>aa  preview the change (colored diff) -> ga/<CR> apply, q/<Esc> cancel
--   :w          save when happy (apply only touches the buffer, never disk)
-- ------------------------------------------------------
-- Prompt builders (copy a prompt to the clipboard):
--   <leader>ai  init        system prompt: tool protocol + output format
--   <leader>aI  init_proj   "document this repo" -> CLAUDE.md (like /init)
--   <leader>ap  plan        goal + context -> step-by-step plan
--   <leader>ax  context     ~20 lines around the cursor
--   <leader>af  fix         error message + file context (asks for a diff)
--   <leader>ar  refactor    selection -> "refactor this" (full replacement)
--   <leader>ao  code        selection -> "modify this code" (full replacement)
--   <leader>ad  code_diff   selection -> "return ONLY a diff"
--   (each prepends "File: <repo-relative path>" so replies target the right file)
-- Runtime (act on the clipboard / buffer):
--   <leader>at  tool        run a ```tool block (find_file/read_file/list_dir/
--                           grep/git_diff), copy results back
--   <leader>aa  apply       apply a diff or Type:full reply, with diff preview
--   <leader>aW  write_doc   drop an LLM markdown reply into a CLAUDE.md buffer
-- Ex commands mirror these (:AgentInit, :AgentTool, :AgentApply, ...) and
-- :AgentAddFile / :AgentCode / :AgentDiff / :AgentRefactor have no keymap.
-- ======================================================

-- Load the agent module
local agent = require("agent")

-- Helper to attach descriptions to keymaps
local function opts(desc)
  return { noremap = true, silent = true, desc = "Agent: " .. desc }
end

-- Wrap a selection-based agent fn so the keymap leaves visual mode FIRST.
-- which-key (shipped by LazyVim) disturbs the live visual state when it
-- triggers a <leader> mapping, so reading getpos("v")/getpos(".") mid-callback
-- is unreliable. Feeding <Esc> synchronously (the "x" flag) updates the
-- '< / '> marks before the fn runs -- the same path the :Agent* commands use.
-- In normal mode the <Esc> is a harmless no-op and the last marks are reused.
local function sel(fn)
  return function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    fn()
  end
end

-- ======================================================
-- KEYMAPS
-- Use "x" instead of "v" to avoid weird select-mode behaviors.
-- Map in both "n" and "x" so you can press the keys AFTER exiting visual mode
-- and it will still act on your last selection.
-- ======================================================

vim.keymap.set({ "n", "x" }, "<leader>ai", agent.init, opts("Initialize prompt"))
vim.keymap.set("n", "<leader>aI", agent.init_project, opts("Document repo (CLAUDE.md)"))
vim.keymap.set("n", "<leader>aW", agent.write_doc, opts("Write reply to CLAUDE.md buffer"))
vim.keymap.set("n", "<leader>at", agent.tool, opts("Run tool call from clipboard"))
vim.keymap.set({ "n", "x" }, "<leader>ap", sel(agent.plan), opts("Plan task"))
vim.keymap.set({ "n", "x" }, "<leader>ax", agent.context, opts("Surrounding context"))
vim.keymap.set({ "n", "x" }, "<leader>af", sel(agent.fix), opts("Fix error"))

-- Commands relying primarily on selections
vim.keymap.set({ "n", "x" }, "<leader>ar", sel(agent.refactor), opts("Refactor selection"))
vim.keymap.set({ "n", "x" }, "<leader>ao", sel(agent.code), opts("Modify selection"))
vim.keymap.set({ "n", "x" }, "<leader>ad", sel(agent.code_diff), opts("Diff selection"))
vim.keymap.set({ "n", "x" }, "<leader>aa", sel(agent.apply), opts("Apply from clipboard"))

-- ======================================================
-- EX COMMANDS
-- ======================================================

vim.api.nvim_create_user_command("AgentInit", agent.init, { desc = "Agent: Initialize prompt" })
vim.api.nvim_create_user_command("AgentInitProject", agent.init_project, { desc = "Agent: Document repo (CLAUDE.md)" })
vim.api.nvim_create_user_command("AgentWriteDoc", agent.write_doc, { desc = "Agent: Write reply to CLAUDE.md buffer" })
vim.api.nvim_create_user_command("AgentTool", agent.tool, { desc = "Agent: Run tool call from clipboard" })
vim.api.nvim_create_user_command("AgentAddFile", agent.add_file, { desc = "Agent: Add current file" })
vim.api.nvim_create_user_command("AgentContext", agent.context, { desc = "Agent: Surrounding context" })
vim.api.nvim_create_user_command("AgentPlan", agent.plan, { desc = "Agent: Plan task" })
vim.api.nvim_create_user_command("AgentFix", agent.fix, { desc = "Agent: Fix error" })

-- Visual commands (range = true allows :'<,'>AgentApply to pass visual marks correctly)
vim.api.nvim_create_user_command("AgentCode", agent.code, { range = true, desc = "Agent: Modify selection" })
vim.api.nvim_create_user_command("AgentDiff", agent.code_diff, { range = true, desc = "Agent: Diff selection" })
vim.api.nvim_create_user_command("AgentRefactor", agent.refactor, { range = true, desc = "Agent: Refactor selection" })
vim.api.nvim_create_user_command(
  "AgentApply",
  agent.apply,
  { range = true, desc = "Agent: Apply diff/code to selection" }
)

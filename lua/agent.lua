local M = {}

-- ======================================================
-- CORE HELPERS
-- ======================================================

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO)
end

-- Above this size, loading the clipboard is painful (browser chats lag, message
-- limits, no chance to review/trim). copy() falls back to a scratch buffer.
local MAX_CLIPBOARD_CHARS = 80000

-- Open text in a throwaway scratch buffer for manual copy/review. The user
-- yanks what they need (e.g. :%y+ for all, or visual-select a portion).
local function open_scratch(text, name)
  vim.cmd("botright split")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n"))
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  pcall(vim.api.nvim_buf_set_name, buf, name or "agent://output")
end

local function copy(text)
  -- Large output: a buffer beats the clipboard (review/trim, no paste lag).
  if #text > MAX_CLIPBOARD_CHARS then
    open_scratch(text, "agent://output")
    notify(
      ("Output is large (%d KB) -- opened in a buffer. Copy what you need (:%%y+ for all)."):format(
        math.floor(#text / 1024)
      ),
      vim.log.levels.WARN
    )
    return
  end

  if vim.fn.has("clipboard") == 1 then
    vim.fn.setreg("+", text)
  else
    vim.fn.setreg('"', text)
    notify("Copied to unnamed register (no system clipboard found)")
    return
  end
  notify("Agent prompt copied to clipboard")
end

-- ------------------------------------------------------
-- Visual selection (safe against MAXCOL and linewise)
-- ------------------------------------------------------
local function get_visual()
  local mode = vim.fn.mode()
  local s, e, linewise

  if mode == "v" or mode == "V" or mode == "\22" then
    -- Called while STILL in visual mode: the '< and '> marks are only
    -- updated when you LEAVE visual mode, so they'd be stale here.
    -- Use the live endpoints instead: "v" = selection anchor, "." = cursor.
    s = vim.fn.getpos("v")
    e = vim.fn.getpos(".")
    linewise = (mode == "V")
  else
    -- Called from normal mode: use the marks from the last selection.
    s = vim.fn.getpos("'<")
    e = vim.fn.getpos("'>")
    linewise = false
  end

  if s[2] == 0 or e[2] == 0 then
    return ""
  end

  -- The cursor may be before the anchor; normalize so s precedes e.
  if (s[2] > e[2]) or (s[2] == e[2] and s[3] > e[3]) then
    s, e = e, s
  end

  local lines = vim.fn.getline(s[2], e[2])
  if #lines == 0 then
    return ""
  end

  local max_col = 2147483647

  -- Linewise selection ('V') sets s[3] and e[3] to 0 (or live cursor cols);
  -- either way we want whole lines. Charwise uses 1-based byte indices.
  local start_col, end_col
  if linewise then
    start_col, end_col = 1, -1
  else
    start_col = s[3] > 0 and s[3] or 1
    end_col = (e[3] == max_col or e[3] == 0) and -1 or e[3]
  end

  if s[2] == e[2] then
    lines[1] = lines[1]:sub(start_col, end_col)
  else
    lines[1] = lines[1]:sub(start_col)
    if end_col ~= -1 then
      lines[#lines] = lines[#lines]:sub(1, end_col)
    end
  end

  return table.concat(lines, "\n")
end

-- ------------------------------------------------------
-- Git diff (current file only)
-- ------------------------------------------------------
local function git_diff()
  local file = vim.fn.expand("%:p")
  if file == "" then
    return ""
  end

  local diff = vim.fn.system("git diff -- " .. vim.fn.shellescape(file))
  if vim.v.shell_error ~= 0 or diff == "" then
    return ""
  end

  return "```diff\n" .. diff .. "\n```"
end

-- ------------------------------------------------------
-- Surrounding context
-- ------------------------------------------------------
local function surround(n)
  local c = vim.api.nvim_win_get_cursor(0)
  local l = c[1]

  local s = math.max(1, l - n)
  local e = l + n

  local lines = vim.api.nvim_buf_get_lines(0, s - 1, e, false)
  return table.concat(lines, "\n"), s, e
end

-- ------------------------------------------------------
-- Paths
-- ------------------------------------------------------

-- Repo root for the current file (falls back to cwd outside a git repo).
local function repo_root()
  local base = vim.fn.expand("%:p:h")
  if base == "" then
    base = vim.fn.getcwd()
  end
  local root = vim.fn.systemlist({ "git", "-C", base, "rev-parse", "--show-toplevel" })[1]
  if vim.v.shell_error ~= 0 or not root or root == "" then
    return vim.fn.getcwd()
  end
  return root
end

-- Repo-relative path of the current file, for the File: header the LLM echoes
-- back (M.apply resolves it against the repo root). Falls back gracefully.
local function rel_path()
  local full = vim.fn.expand("%:p")
  if full == "" then
    return vim.fn.expand("%:t") -- unnamed buffer
  end
  local root = repo_root()
  if full:sub(1, #root + 1) == root .. "/" then
    return full:sub(#root + 2)
  end
  return vim.fn.fnamemodify(full, ":~:.")
end

-- ======================================================
-- CONTEXT BUILDER
-- ======================================================

local function context(include_selection)
  local lang = vim.bo.filetype ~= "" and vim.bo.filetype or "text"
  local full = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")

  local parts = {}

  table.insert(parts, ("File: %s (%s)"):format(rel_path(), lang))

  local diff = git_diff()
  if diff ~= "" then
    table.insert(parts, "Unstaged diff:\n" .. diff)
  end

  if include_selection then
    local sel = get_visual()
    if sel ~= "" then
      table.insert(parts, "Selected code:\n```" .. lang .. "\n" .. sel .. "\n```")
    else
      table.insert(parts, "Full file:\n```" .. lang .. "\n" .. full .. "\n```")
    end
  else
    table.insert(parts, "Full file:\n```" .. lang .. "\n" .. full .. "\n```")
  end

  return table.concat(parts, "\n\n")
end

-- ======================================================
-- SHARED OUTPUT RULES (single source of truth)
-- These are appended to every prompt that produces applyable output, so the
-- responses stay compatible with M.apply's parser.
-- ======================================================

-- For prompts that should return a unified diff (apply via <leader>aa).
local DIFF_RULES = [[Diff requirements (STRICT — the patch is applied programmatically):
* Every hunk MUST start with a proper @@ -<old>,<n> +<new>,<m> @@ header.
* Include at least 3 lines of UNCHANGED context above and below each change.
* The FIRST character of every line is the marker, with NO space after it:
  "-" = removed line, "+" = added line, " " (single space) = unchanged context.
  The line's real content begins at column 2. Do NOT write "- code" (that adds a
  spurious leading space); write "-code".
* Only changed lines get "-"/"+". Unchanged lines stay as " " context — never
  mark an identical line as both removed and added.
* Do not abbreviate, elide, or write "..." inside the diff.
* Keep indentation/whitespace byte-for-byte identical to the source.

Example (note: no space between the marker and the code):
```diff
@@ -3,5 +3,5 @@
 unchanged context line
 another context line
-old line to remove
+new line to add
 trailing context line
```]]

-- For prompts that should return a full replacement block for the selection.
local CODE_RULES = [[Output rules (STRICT — your reply is applied programmatically):
* Return ONLY the complete replacement inside ONE fenced code block. No prose.
* Emit every line of the replacement — never abbreviate or write "...".
* Keep indentation/whitespace consistent with the surrounding code.]]

-- Generated from the TOOLS table in the CONTEXT TOOLS section below. Declared
-- here (before M.init) so the system prompt and the dispatcher share one
-- definition of the tool set; assigned once at load time.
local tool_signatures

-- Forward declaration: defined in the APPLY ENGINE section but called earlier
-- by M.tool's write_file handling. Assigned once at load time.
local preview_and_commit

-- ======================================================
-- INIT (CRITICAL: enforce structured output)
-- ======================================================

function M.init()
  local prompt = [[
You are a senior software engineer acting as a Neovim coding agent.

════════════════════════════════════════════════════════════════════════════════
TOOL PROTOCOL (MANDATORY — ALWAYS USE TOOLS BEFORE ANSWERING)
════════════════════════════════════════════════════════════════════════════════

You MUST use tools to gather context before writing any code. NEVER guess file
contents, directory structure, or existing code. Always verify with tools first.

If you need code or files that were not provided, request them and STOP — do not
also answer in the same reply. Emit ONLY a <tool> block, e.g.:

<tool>
find_file AppDbContext.cs
read_file src/Domain/Entities/Project.cs:1-40
</tool>

Available tools:
]] .. tool_signatures .. [[

Tool rules:
* Paths are relative to the repo root. Never request files outside it.
* You may request several tools at once (one per line), but only a few file
  reads per turn -- use find_file/grep to narrow down, then read what you need.
* I will run them and paste the results back, then you continue.
* NEVER invent file contents — request the file instead. This is the #1 rule.

* The bash tool runs commands in the repo root. The user must confirm before
  execution, so prefer read-only commands (ls, cat, git log) when possible.

WRITING FILES:
To write a file, put write_file <path> inside a <tool> block followed by a
fenced code block with the content. You can write MULTIPLE files in one <tool>
block. Each write_file gets its own fenced block. Example:he change is shown to me as a diff to accept or reject. Example:

<tool>
write_file src/Domain/Interfaces/IFoo.cs

```csharp
namespace Domain.Interfaces;

public interface IFoo { }
```

write_file src/Domain/Models/AppConfig.cs
```csharp 
namespace Domain.Models; 

public class AppConfig { } 
```
</tool>


════════════════════════════════════════════════════════════════════════════════
OUTPUT FORMAT (STRICT):
════════════════════════════════════════════════════════════════════════════════

Use <tool> blocks for ALL context gathering and file writing. Only use the
formats below for your FINAL answer after you have gathered all context.

Return ONLY ONE format. Prefer FORMAT 1 (patch); use FORMAT 2 (full file) only
for a new file or a near-total rewrite.

FORMAT 1 — PATCH MODE:
File: <path>
Type: patch

```diff
<unified diff only>
```

]] .. DIFF_RULES .. [[


FORMAT 2 — FULL FILE MODE:
File: <path>
Type: full

```<lang>
<entire file>
```

RULES:
* No explanations
* No extra text
* Always include file name
* Use <tool> blocks FIRST to read files, THEN produce your final answer
  ]]

  -- If CLAUDE.md exists at the repo root, include it as project context
  -- so the agent is aware of project conventions, architecture, and commands.
  local root = repo_root()
  local claude_path = root .. "/CLAUDE.md"
  if vim.fn.filereadable(claude_path) == 1 then
    local ok, lines = pcall(vim.fn.readfile, claude_path)
    if ok and type(lines) == "table" and #lines > 0 then
      local content = table.concat(lines, "\n")
      prompt = "PROJECT CONTEXT (CLAUDE.md from repo root — follow these conventions):\n\n```markdown\n"
        .. content
        .. "\n```\n\n"
        .. prompt
    end
  end

  copy(prompt)
end

-- ======================================================
-- PROJECT INIT (analogous to Claude Code's /init)
-- Gathers a compact repo overview and builds a "document this codebase"
-- prompt. Like every other command it only fills the clipboard: paste into
-- your LLM, then save the reply as CLAUDE.md (or apply it as a new file).
-- ======================================================

-- Read up to max_lines from a file; returns nil on any error.
local function read_head(path, max_lines)
  local ok, lines = pcall(vim.fn.readfile, path, "", max_lines)
  if not ok or type(lines) ~= "table" then
    return nil
  end
  return table.concat(lines, "\n")
end

-- Build a token-bounded snapshot of the repo: the tracked-file list (respects
-- .gitignore) plus the contents of key manifest/readme files.
local function repo_overview()
  local base = vim.fn.expand("%:p:h")
  if base == "" then
    base = vim.fn.getcwd()
  end

  local root = vim.fn.systemlist({ "git", "-C", base, "rev-parse", "--show-toplevel" })[1]
  if vim.v.shell_error ~= 0 or not root or root == "" then
    return nil, "Not inside a git repository"
  end

  local files = vim.fn.systemlist({ "git", "-C", root, "ls-files" })
  if vim.v.shell_error ~= 0 then
    return nil, "git ls-files failed"
  end

  -- Cap the file list so the prompt stays a sane size.
  local MAX_FILES = 400
  local truncated = #files > MAX_FILES
  local listed = {}
  for i = 1, math.min(#files, MAX_FILES) do
    listed[i] = files[i]
  end

  -- Quote the contents of build/config/readme files; the model reads these to
  -- infer commands, stack and conventions.
  local function is_key(path)
    local base_name = path:match("[^/]+$") or path
    return base_name:match("^[Rr][Ee][Aa][Dd][Mm][Ee]")
      or base_name == "package.json"
      or base_name == "go.mod"
      or base_name == "Cargo.toml"
      or base_name == "pyproject.toml"
      or base_name == "requirements.txt"
      or base_name == "Gemfile"
      or base_name == "pom.xml"
      or base_name == "build.gradle"
      or base_name == "Makefile"
      or base_name == "justfile"
      or base_name == "docker-compose.yml"
      or base_name:match("%.sln$")
      or base_name:match("%.csproj$")
      or base_name:match("%.toml$")
  end

  local blobs = {}
  local budget = 12000 -- rough char cap across all quoted files
  for _, path in ipairs(files) do
    if budget <= 0 then
      break
    end
    if is_key(path) then
      local content = read_head(root .. "/" .. path, 150)
      if content and content ~= "" then
        content = content:sub(1, budget)
        budget = budget - #content
        table.insert(blobs, ("### %s\n```\n%s\n```"):format(path, content))
      end
    end
  end

  local parts = {
    "Repository root: " .. root,
    ("Tracked files (%d%s):\n%s"):format(
      #listed,
      truncated and (" of " .. #files .. ", list truncated") or "",
      table.concat(listed, "\n")
    ),
  }
  if #blobs > 0 then
    table.insert(parts, "Key files:\n\n" .. table.concat(blobs, "\n\n"))
  end

  return table.concat(parts, "\n\n")
end

function M.init_project()
  local overview, err = repo_overview()
  if not overview then
    notify(err or "Could not read repository", vim.log.levels.WARN)
    return
  end

  local instructions = [[
You are documenting a codebase for engineers and AI agents. From the repository
overview below, write a CLAUDE.md in Markdown with these sections (infer from
the files provided; do NOT invent features that aren't evidenced):

# Project Overview   — what it is, primary language/framework, purpose
# Architecture       — major components/directories and how they relate
# Build / Test / Run — exact commands taken from manifests/Makefile/scripts
# Conventions        — code style, naming and patterns you can infer
# Key Directories    — one line each for the important folders

Output ONLY the CLAUDE.md contents inside a single fenced ```markdown block.]]

  copy(instructions .. "\n\nREPOSITORY OVERVIEW:\n\n" .. overview)
end

-- Remove a SINGLE outermost ``` fence, keeping nested code blocks intact.
-- (A regex like ```(.-)``` would stop at the first inner fence -- wrong for a
-- markdown doc that contains its own ```bash blocks.)
local function strip_outer_fence(text)
  local lines = vim.split(text, "\n")

  local first = 1
  while first <= #lines and lines[first]:match("^%s*$") do
    first = first + 1
  end
  if first > #lines or not lines[first]:match("^```") then
    return text
  end

  local last = #lines
  while last > first and not lines[last]:match("^```%s*$") do
    last = last - 1
  end
  if last <= first then
    return text
  end

  local out = {}
  for i = first + 1, last - 1 do
    table.insert(out, lines[i])
  end
  return table.concat(out, "\n")
end

-- Drop the LLM's markdown reply (from the clipboard) into a CLAUDE.md buffer at
-- the repo root, ready to review and :w. Pairs with M.init_project. Never
-- touches disk -- you save when happy.
function M.write_doc()
  local resp = vim.fn.has("clipboard") == 1 and vim.fn.getreg("+") or vim.fn.getreg('"')
  if resp == "" then
    notify("Clipboard empty", vim.log.levels.WARN)
    return
  end

  local body = strip_outer_fence(resp)

  local root = repo_root()
  local path = root .. "/CLAUDE.md"
  local existed = vim.fn.filereadable(path) == 1

  vim.cmd.edit(vim.fn.fnameescape(path))
  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(body, "\n"))
  vim.bo.filetype = "markdown"

  notify(
    existed and "CLAUDE.md exists -- buffer overwritten, review then :w" or "CLAUDE.md ready in buffer -- :w to save"
  )
end

-- ======================================================
-- CONTEXT TOOLS (simulated tool calling)
-- The LLM emits a <tool>…</tool> block requesting files/searches; M.tool() runs the
-- read-only request and copies the result back for you to paste. A manual
-- ReAct loop where you are the runtime.
-- ======================================================

local TOOL_MAX_FILE_LINES = 800
local TOOL_MAX_LIST = 500
local TOOL_MAX_GREP = 100
-- Cap file reads per turn so a single tool block can't dump the whole repo into
-- one paste. The model is told to ask for the rest on the next turn.
local TOOL_MAX_FILES_PER_TURN = 3
-- bash output can be voluminous (build logs); give it more headroom than grep.
local TOOL_MAX_BASH_LINES = 300

-- Cap a list in place to n entries, returning a "truncated" note (or "").
local function cap(list, n, label)
  if #list <= n then
    return ""
  end
  for i = #list, n + 1, -1 do
    list[i] = nil
  end
  return ("\n... (truncated to %d %s)"):format(n, label)
end

-- Resolve an LLM-supplied path against the repo root, refusing anything that
-- escapes it (../.., absolute paths, ~). Returns abs path or nil,err.
local function safe_path(root, rel)
  rel = vim.trim(rel or "")
  if rel == "" then
    return nil, "empty path"
  end

  local full
  if rel:sub(1, 1) == "/" or rel:sub(1, 1) == "~" then
    full = vim.fn.fnamemodify(vim.fn.expand(rel), ":p")
  else
    full = vim.fn.fnamemodify(root .. "/" .. rel, ":p")
  end

  local root_abs = (vim.fn.fnamemodify(root, ":p"):gsub("/$", ""))
  local full_norm = (full:gsub("/$", ""))
  if full_norm == root_abs or full_norm:sub(1, #root_abs + 1) == root_abs .. "/" then
    return full_norm
  end
  return nil, "path escapes repo root: " .. rel
end

local function tool_read_file(root, args)
  local path, lo, hi = args:match("^(%S+):(%d+)%-(%d+)$")
  if not path then
    path = vim.trim(args)
  end

  local abs, err = safe_path(root, path)
  if not abs then
    return "ERROR: " .. err
  end
  if vim.fn.filereadable(abs) ~= 1 then
    return "ERROR: not a readable file: " .. path
  end

  local lines = vim.fn.readfile(abs)
  if lo then
    lo, hi = tonumber(lo), tonumber(hi)
    local sliced = {}
    for i = lo, math.min(hi, #lines) do
      table.insert(sliced, lines[i])
    end
    lines = sliced
  end

  local note = cap(lines, TOOL_MAX_FILE_LINES, "lines")
  local lang = vim.filetype.match({ filename = abs }) or ""
  return ("```%s\n%s\n```%s"):format(lang, table.concat(lines, "\n"), note)
end

local function tool_list_dir(root, args)
  local cmd = { "git", "-C", root, "ls-files" }
  local sub = vim.trim(args or "")
  if sub ~= "" then
    local _, err = safe_path(root, sub)
    if err then
      return "ERROR: " .. err
    end
    table.insert(cmd, "--")
    table.insert(cmd, sub)
  end

  local files = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return "ERROR: git ls-files failed"
  end
  if #files == 0 then
    return "(no tracked files)"
  end

  local note = cap(files, TOOL_MAX_LIST, "entries")
  return table.concat(files, "\n") .. note
end

local function tool_find_file(root, args)
  local q = vim.trim(args or "")
  if q == "" then
    return "ERROR: empty name"
  end

  local files = vim.fn.systemlist({ "git", "-C", root, "ls-files" })
  if vim.v.shell_error ~= 0 then
    return "ERROR: git ls-files failed"
  end

  local ql = q:lower()
  local matches = {}
  for _, f in ipairs(files) do
    if f:lower():find(ql, 1, true) then
      table.insert(matches, f)
    end
  end

  if #matches == 0 then
    return "(no tracked file matching '" .. q .. "')"
  end
  local note = cap(matches, TOOL_MAX_LIST, "matches")
  return table.concat(matches, "\n") .. note
end

local function tool_grep(root, args)
  local pat = vim.trim(args or "")
  if pat == "" then
    return "ERROR: empty pattern"
  end

  -- -I skips binaries; -e handles patterns that begin with "-".
  local res = vim.fn.systemlist({ "git", "-C", root, "grep", "-n", "-I", "-e", pat })
  if vim.v.shell_error ~= 0 then
    return "(no matches)"
  end

  local note = cap(res, TOOL_MAX_GREP, "matches")
  return table.concat(res, "\n") .. note
end

local function tool_git_diff(root)
  local out = vim.fn.system({ "git", "-C", root, "diff" })
  if vim.v.shell_error ~= 0 then
    return "ERROR: git diff failed"
  end
  if out == "" then
    return "(no unstaged changes)"
  end
  return "```diff\n" .. out .. "\n```"
end

local function tool_bash(root, args)
  local cmd = vim.trim(args or "")
  if cmd == "" then
    return "ERROR: empty command"
  end

  local confirm = vim.fn.confirm("Run command?: " .. cmd, "&Yes\n&No", 2)
  if confirm ~= 1 then
    return "Command cancelled by user"
  end

  local full_cmd = ("cd %s && %s 2>&1"):format(vim.fn.shellescape(root), cmd)
  local out = vim.fn.system(full_cmd)
  local lines = vim.split(out, "\n")
  if #lines > 0 and lines[#lines] == "" then
    lines[#lines] = nil
  end

  local prefix = ""
  if vim.v.shell_error ~= 0 then
    prefix = ("Exit code: %d\n"):format(vim.v.shell_error)
  end

  local note = cap(lines, TOOL_MAX_BASH_LINES, "lines")
  return prefix .. table.concat(lines, "\n") .. note
end

local function tool_diagnostics(root, args)
  local path = vim.trim(args or "")
  local diagnostics
  local header

  if path ~= "" then
    local abs, err = safe_path(root, path)
    if not abs then
      return "ERROR: " .. err
    end
    local bufnr = vim.fn.bufnr(abs)
    if bufnr == -1 then
      return "(no diagnostics — file not open in a buffer)"
    end
    diagnostics = vim.diagnostic.get(bufnr)
    header = ("Diagnostics for %s:"):format(path)
  else
    diagnostics = vim.diagnostic.get()
    header = "Workspace diagnostics:"
  end

  if #diagnostics == 0 then
    return "(no diagnostics)"
  end

  table.sort(diagnostics, function(a, b)
    if a.severity ~= b.severity then
      return a.severity < b.severity
    end
    if a.bufnr ~= b.bufnr then
      return a.bufnr < b.bufnr
    end
    return a.lnum < b.lnum
  end)

  local sev_names = { [1] = "ERROR", [2] = "WARN", [3] = "INFO", [4] = "HINT" }
  local lines = {}
  for _, d in ipairs(diagnostics) do
    local buf_name = vim.api.nvim_buf_get_name(d.bufnr)
    if buf_name:sub(1, #root + 1) == root .. "/" then
      buf_name = buf_name:sub(#root + 2)
    end
    local sev = sev_names[d.severity] or "OTHER"
    table.insert(lines, ("%s:%d:%d %s: %s"):format(buf_name, d.lnum + 1, d.col + 1, sev, d.message))
  end

  local note = cap(lines, 100, "diagnostics")
  return header .. "\n" .. table.concat(lines, "\n") .. note
end

-- SINGLE SOURCE OF TRUTH for the tool set. The dispatcher, the system-prompt
-- signatures (tool_signatures) and the TOOL RESULTS reminder (tools_reminder)
-- are all derived from this -- add a tool here and every surface updates.
-- "heavy" tools count against the per-turn file-read limit.
local TOOLS = {
  { name = "find_file", arg = "<name>", help = "locate a tracked file by name", run = tool_find_file },
  {
    name = "read_file",
    arg = "<path>[:a-b]",
    help = "read a file (optional line range)",
    run = tool_read_file,
    heavy = true,
  },
  {
    name = "diagnostics",
    arg = "[<path>]",
    help = "get LSP diagnostics (workspace or single file)",
    run = tool_diagnostics,
  },
  { name = "bash", arg = "<command>", help = "run a bash command in the repo root", run = tool_bash },
  { name = "list_dir", arg = "[<path>]", help = "list tracked files", run = tool_list_dir, aliases = { "tree" } },
  { name = "grep", arg = "<pattern>", help = "search the repo", run = tool_grep },
  { name = "git_diff", arg = "", help = "current unstaged changes", run = tool_git_diff },
  {
    name = "write_file",
    arg = "<path>",
    help = "create or replace a file — put the full new content in a fenced code block inside the same <tool> block:",
    note = "    <tool>\n    write_file src/services/auth.py\n\n    ```python\n    def verify(token: str) -> bool:\n        return token == SECRET\n    ```\n    </tool>",
    write = true,
  },
}

-- Derive the dispatch map (name/alias -> spec), the signature list and the
-- name list once.
local TOOL_BY_NAME = {}
local tool_names = {}
local sig_lines = {}
for _, t in ipairs(TOOLS) do
  TOOL_BY_NAME[t.name] = t
  for _, alias in ipairs(t.aliases or {}) do
    TOOL_BY_NAME[alias] = t
  end
  table.insert(tool_names, t.name)
  local sig = t.arg ~= "" and (t.name .. " " .. t.arg) or t.name
  table.insert(sig_lines, ("  %-26s %s"):format(sig, t.help))
  if t.note then
    table.insert(sig_lines, t.note)
  end
end

local TOOL_NAMES_CSV = table.concat(tool_names, ", ")
tool_signatures = table.concat(sig_lines, "\n") -- assign the forward-declared upvalue

-- Re-stated at the end of every TOOL RESULTS message so the protocol stays in
-- context as a long conversation pushes the original system prompt out of focus.
local tools_reminder = "---\n"
  .. "Need more context? Reply with ONLY a <tool> block (one call per line):\n"
  .. tool_signatures
  .. ("\nRequest at most %d files per turn; ask for the rest next turn."):format(TOOL_MAX_FILES_PER_TURN)
  .. "\nOtherwise, reply with your final answer in the required output format."

function M.tool()
  local resp = vim.fn.has("clipboard") == 1 and vim.fn.getreg("+") or vim.fn.getreg('"')
  if resp == "" then
    notify("Clipboard empty", vim.log.levels.WARN)
    return
  end

  -- Walk the response line by line, collecting tool-call lines and write_file
  -- content from <tool>…</tool> blocks. Fenced code blocks inside <tool>
  -- provide content for write_file calls. This is unambiguous because </tool>
  -- never appears inside markdown fences.
  local tool_lines = {}
  local content_blocks = {}
  local resp_lines = vim.split(resp, "\n")
  local i = 1
  while i <= #resp_lines do
    local line = resp_lines[i]
    if line:match("^<tool>%s*$") then
      -- Inside a <tool> block: collect tool-call lines and content blocks
      i = i + 1
      while i <= #resp_lines and not resp_lines[i]:match("^</tool>%s*$") do
        local inner = resp_lines[i]
        if inner:match("^```%w*") then
          -- Fenced code block inside <tool>: write_file content
          local body = {}
          i = i + 1
          while i <= #resp_lines and not resp_lines[i]:match("^```%s*$") do
            table.insert(body, resp_lines[i])
            i = i + 1
          end
          i = i + 1 -- skip closing ```
          table.insert(content_blocks, table.concat(body, "\n"))
        else
          local trimmed = vim.trim(inner)
          if trimmed ~= "" then
            table.insert(tool_lines, trimmed)
          end
          i = i + 1
        end
      end
      i = i + 1 -- skip </tool>
    else
      i = i + 1
    end
  end

  if #tool_lines == 0 then
    notify("No <tool> block found in clipboard", vim.log.levels.WARN)
    return
  end

  local root = repo_root()
  local results = {}
  local writes = {} -- queued write_file calls, applied via preview after reads
  local heavy_used = 0

  local content_idx = 0
  for _, line in ipairs(tool_lines) do
    if line ~= "" then
      local name, args = line:match("^(%S+)%s*(.*)$")
      local tool = TOOL_BY_NAME[name]
      if tool and tool.write then
        content_idx = content_idx + 1
        local content = content_blocks[content_idx]
        if not content then
          table.insert(
            results,
            ("TOOL RESULT — %s\nERROR: provide the file content in a fenced block inside the <tool> block"):format(
              line
            )
          )
        else
          table.insert(writes, { path = vim.trim(args), content = content, line = line })
        end
      else
        local out
        if not tool then
          out = "ERROR: unknown tool '" .. (name or "") .. "'. Valid: " .. TOOL_NAMES_CSV
        elseif tool.heavy and heavy_used >= TOOL_MAX_FILES_PER_TURN then
          out = ("(skipped: %d-files-per-turn limit reached -- request this on the next turn)"):format(
            TOOL_MAX_FILES_PER_TURN
          )
        else
          if tool.heavy then
            heavy_used = heavy_used + 1
          end
          out = tool.run(root, args)
        end
        table.insert(results, ("TOOL RESULT — %s\n%s"):format(line, out))
      end
    end
  end

  if #results == 0 and #writes == 0 then
    notify("<tool> block was empty", vim.log.levels.WARN)
    return
  end

  local function finalize()
    copy("TOOL RESULTS (paste back to continue):\n\n" .. table.concat(results, "\n\n") .. "\n\n" .. tools_reminder)
  end

  -- Reads are done; now preview each write_file in turn, then copy everything.
  if #writes == 0 then
    finalize()
    return
  end

  local function run_writes(i)
    if i > #writes then
      finalize()
      return
    end
    local w = writes[i]
    local abs, err = safe_path(root, w.path)
    if not abs then
      table.insert(results, ("TOOL RESULT — %s\nERROR: %s"):format(w.line, err))
      run_writes(i + 1)
      return
    end
    vim.cmd.edit(vim.fn.fnameescape(abs)) -- new files open as an empty buffer
    preview_and_commit(vim.split(w.content, "\n"), {
      label = ("[write %d/%d] %s"):format(i, #writes, w.path),
      on_done = function(outcome)
        local status = ({
          applied = "applied and saved",
          cancelled = "rejected by user",
          nochange = "no change (identical content)",
        })[outcome] or tostring(outcome)
        table.insert(results, ("TOOL RESULT — %s\n%s"):format(w.line, status))
        -- Copy results to clipboard immediately so the user can paste back
        -- to the model without waiting for all writes to finish.
        copy("TOOL RESULTS (paste back to continue):\n\n" .. table.concat(results, "\n\n") .. "\n\n" .. tools_reminder)
        run_writes(i + 1)
      end,
    })
  end
  run_writes(1)
end

-- ======================================================
-- TASK COMMANDS
-- ======================================================

function M.plan()
  local goal = vim.fn.input("Goal: ")
  copy(("Goal: %s\n\nContext:\n%s\n\nReturn step-by-step plan only."):format(goal, context(true)))
end

function M.add_file()
  copy("Analyze this file:\n\n" .. context(false))
end

function M.context()
  local c, s, e = surround(20)
  copy(("Context lines %d-%d:\n\n%s"):format(s, e, c))
end

function M.fix()
  local err = vim.fn.input("Error: ")
  -- Full-file context is included, so a precise unified diff is feasible.
  copy(("Fix this error:\n%s\n\nContext:\n%s\n\n%s"):format(err, context(true), DIFF_RULES))
end

function M.refactor()
  local sel = get_visual()
  if sel == "" then
    notify("No selection", vim.log.levels.WARN)
    return
  end
  copy(("File: %s\n\nRefactor this:\n```%s\n%s\n```\n\n%s"):format(rel_path(), vim.bo.filetype, sel, CODE_RULES))
end

function M.code()
  local sel = get_visual()
  if sel == "" then
    notify("No selection", vim.log.levels.WARN)
    return
  end
  copy(
    ("File: %s\n\nModify this code only:\n```%s\n%s\n```\n\n%s"):format(rel_path(), vim.bo.filetype, sel, CODE_RULES)
  )
end

function M.code_diff()
  local sel = get_visual()
  if sel == "" then
    notify("No selection", vim.log.levels.WARN)
    return
  end
  copy(("File: %s\n\nReturn ONLY diff:\n```diff\n%s\n```\n\n%s"):format(rel_path(), sel, DIFF_RULES))
end

-- ======================================================
-- APPLY ENGINE (CURSOR-LIKE SAFE MODE)
-- ======================================================

-- Helper to safely calculate columns for nvim_buf_set_text
-- FIX: nvim_buf_set_text requires valid 0-based exclusive column indices.
-- Passing -1 or MAXCOL causes API errors and aborts the replacement.
local function safe_cols(s, e)
  local max_col = 2147483647
  local start_col = s[3] > 0 and (s[3] - 1) or 0

  local end_col = e[3]
  if end_col == max_col or end_col == 0 then
    -- Get actual line length to replace to the end of the line safely
    local line = vim.api.nvim_buf_get_lines(0, e[2] - 1, e[2], false)[1] or ""
    end_col = #line
  else
    -- e[3] is 1-based inclusive from getpos, nvim_buf_set_text needs 0-based exclusive
    end_col = e[3]
  end

  return start_col, end_col
end

-- FIX: Extract the LAST code block in the response.
-- LLMs often output explanations or multiple snippets.
-- The main replacement is almost always the last block.
local function extract_last_code_block(text)
  local last_code = nil
  for code in text:gmatch("```[a-zA-Z]*\n(.-)\n```") do
    last_code = code
  end
  if not last_code then
    for code in text:gmatch("```\n(.-)\n```") do
      last_code = code
    end
  end
  return last_code
end

local function extract_last_diff_block(text)
  local last_diff = nil
  for diff in text:gmatch("```diff\n(.-)\n```") do
    last_diff = diff
  end
  return last_diff
end

-- Apply a unified diff to the CURRENT BUFFER's contents, never the file on disk.
-- We dump the buffer to a throwaway copy, git-apply onto that copy, then load the
-- result back. This keeps unsaved edits + undo intact and avoids the W12 desync
-- you get from patching the real file out from under a modified buffer.
local function git_apply_lines(diff)
  if not diff:match("@@") then
    return nil, "diff has no @@ hunk header"
  end

  local bufnr = 0
  local orig = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local target = dir .. "/buf"
  vim.fn.writefile(orig, target)

  -- Rewrite the patch headers to point at our temp copy (resolved via -p1).
  -- Drop "diff --git"/"index" lines whose paths/hashes won't match the copy.
  local src = vim.split(diff, "\n")
  local has_header = false
  for _, l in ipairs(src) do
    if l:match("^%-%-%- ") then
      has_header = true
      break
    end
  end

  local norm = {}
  if not has_header then
    table.insert(norm, "--- a/buf")
    table.insert(norm, "+++ b/buf")
  end
  for _, l in ipairs(src) do
    if l:match("^diff %-%-git") or l:match("^index ") then
      -- skip
    elseif l:match("^%-%-%- ") then
      table.insert(norm, "--- a/buf")
    elseif l:match("^%+%+%+ ") then
      table.insert(norm, "+++ b/buf")
    else
      table.insert(norm, l)
    end
  end

  local patch = dir .. "/patch.diff"
  vim.fn.writefile(norm, patch)

  -- git apply works outside a repo; --recount tolerates wrong @@ counts.
  local out = vim.fn.system({ "git", "-C", dir, "apply", "--recount", "--whitespace=nowarn", "-p1", patch })
  if vim.v.shell_error ~= 0 then
    vim.fn.delete(dir, "rf")
    return nil, out
  end

  local patched = vim.fn.readfile(target)
  vim.fn.delete(dir, "rf")
  return patched
end

-- Apply a diff that has NO @@/file headers (just context, "-" and "+" lines)
-- by reconstructing the old block (context + deletions) and new block
-- (context + additions), locating the old block verbatim in the buffer, and
-- swapping in the new block. Refuses to guess when the match is missing or
-- ambiguous, so it never half-applies the way the old parser did.
local function context_apply_lines(diff)
  local old_lines, new_lines = {}, {}
  for _, l in ipairs(vim.split(diff, "\n")) do
    if
      l:match("^@@")
      or l:match("^%-%-%- ")
      or l:match("^%+%+%+ ")
      or l:match("^diff %-%-git")
      or l:match("^index ")
    then
      -- header line: ignore
    else
      local tag = l:sub(1, 1)
      local body = l:sub(2)
      if tag == "-" then
        table.insert(old_lines, body)
      elseif tag == "+" then
        table.insert(new_lines, body)
      else
        -- context line (" text") or a bare blank line: belongs to both sides
        table.insert(old_lines, body)
        table.insert(new_lines, body)
      end
    end
  end

  if #old_lines == 0 then
    return nil, "diff has no context/deletions to locate the change"
  end

  local buf = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  -- Locate `old` as a contiguous, UNIQUE block in the buffer.
  -- Returns (start) on a single match, (nil) if none, (nil, true) if ambiguous.
  local function locate(old)
    local found
    for i = 1, #buf - #old + 1 do
      local ok = true
      for j = 1, #old do
        if buf[i + j - 1] ~= old[j] then
          ok = false
          break
        end
      end
      if ok then
        if found then
          return nil, true
        end
        found = i
      end
    end
    return found
  end

  local start, ambiguous = locate(old_lines)

  -- Recovery for a common model mistake: writing "- text"/"+ text" (a space
  -- after the marker) instead of "-text"/"+text". That injects one spurious
  -- leading space into every body. If the exact match failed and EVERY old
  -- line carries that leading space, strip one space from both sides and retry.
  if not start and not ambiguous then
    local all_spaced = true
    for _, l in ipairs(old_lines) do
      if l:sub(1, 1) ~= " " then
        all_spaced = false
        break
      end
    end
    if all_spaced then
      local function lstrip1(t)
        local out = {}
        for _, l in ipairs(t) do
          table.insert(out, l:sub(2))
        end
        return out
      end
      local stripped_old = lstrip1(old_lines)
      local s2, amb2 = locate(stripped_old)
      if s2 then
        old_lines, new_lines = stripped_old, lstrip1(new_lines)
        start, ambiguous = s2, amb2
      end
    end
  end

  if ambiguous then
    return nil, "diff context matches multiple locations; apply manually"
  end
  if not start then
    return nil, "could not locate the diff's context in the buffer"
  end

  -- Splice the new block into the buffer copy and return the full result.
  local out = {}
  for i = 1, start - 1 do
    out[#out + 1] = buf[i]
  end
  for _, l in ipairs(new_lines) do
    out[#out + 1] = l
  end
  for i = start + #old_lines, #buf do
    out[#out + 1] = buf[i]
  end
  return out
end

-- Compute the full buffer that results from replacing the visual selection
-- (s..e, char-precise) with `code` -- without touching the buffer. Mirrors
-- nvim_buf_set_text semantics so the preview matches what would be applied.
local function selection_replaced_lines(s, e, code)
  local sr, er = s[2], e[2]
  local start_col, end_col = safe_cols(s, e)
  local buf = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  local prefix = (buf[sr] or ""):sub(1, start_col)
  local suffix = (buf[er] or ""):sub(end_col + 1)
  local code_lines = vim.split(code, "\n")
  code_lines[1] = prefix .. code_lines[1]
  code_lines[#code_lines] = code_lines[#code_lines] .. suffix

  local out = {}
  for i = 1, sr - 1 do
    out[#out + 1] = buf[i]
  end
  for _, l in ipairs(code_lines) do
    out[#out + 1] = l
  end
  for i = er + 1, #buf do
    out[#out + 1] = buf[i]
  end
  return out
end

-- Show a side-by-side COLORED diff (current vs proposed) and wait for the user
-- to accept (ga / <CR>) or reject (q / <Esc>). Nothing is written to the buffer
-- until accept, and the real file is never touched -- you :w when happy.
function preview_and_commit(new_lines, opts)
  opts = opts or {}
  local tag = opts.label and (opts.label .. " ") or ""
  local function chain(outcome)
    if opts.on_done then
      opts.on_done(outcome)
    end
  end

  local target_buf = vim.api.nvim_get_current_buf()
  local target_win = vim.api.nvim_get_current_win()
  local old_lines = vim.api.nvim_buf_get_lines(target_buf, 0, -1, false)

  if vim.deep_equal(old_lines, new_lines) then
    notify(tag .. "No changes to apply")
    chain("nochange")
    return
  end

  local ft = vim.bo[target_buf].filetype

  -- Proposed content in a scratch buffer, opened in a vertical split.
  vim.cmd("vsplit")
  local prev_win = vim.api.nvim_get_current_win()
  local prev_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(prev_win, prev_buf)
  vim.api.nvim_buf_set_lines(prev_buf, 0, -1, false, new_lines)
  vim.bo[prev_buf].filetype = ft
  vim.bo[prev_buf].buftype = "nofile"
  pcall(vim.api.nvim_buf_set_name, prev_buf, "agent://proposed")

  -- diff mode on both windows -> DiffAdd/DiffDelete/DiffChange highlighting.
  vim.api.nvim_win_call(target_win, function()
    vim.cmd("diffthis")
  end)
  vim.api.nvim_win_call(prev_win, function()
    vim.cmd("diffthis")
  end)
  vim.cmd("redraw")

  local done = false
  local function finish(accept)
    if done then
      return
    end
    done = true
    if vim.api.nvim_win_is_valid(target_win) then
      vim.api.nvim_win_call(target_win, function()
        vim.cmd("diffoff")
      end)
    end
    if vim.api.nvim_win_is_valid(prev_win) then
      vim.api.nvim_win_close(prev_win, true)
    end
    if vim.api.nvim_buf_is_valid(prev_buf) then
      pcall(vim.api.nvim_buf_delete, prev_buf, { force = true })
    end
    if accept and vim.api.nvim_buf_is_valid(target_buf) then
      vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, new_lines)
      -- Save the target buffer to disk. writefile is the most reliable way
      -- (doesn't depend on buftype, window focus, or autocommands). Mark the
      -- buffer as unmodified afterwards so it doesn't show as dirty.
      local bufname = vim.api.nvim_buf_get_name(target_buf)
      if bufname ~= "" then
        vim.fn.writefile(new_lines, bufname)
        vim.bo[target_buf].modified = false
      end
      notify(tag .. "Applied and saved")
    elseif not accept then
      notify(tag .. "Cancelled -- buffer unchanged", vim.log.levels.WARN)
    end
    chain(accept and "applied" or "cancelled")
  end

  for _, key in ipairs({ "ga", "<CR>" }) do
    vim.keymap.set("n", key, function()
      finish(true)
    end, { buffer = prev_buf, nowait = true, desc = "Agent: accept changes" })
  end
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      finish(false)
    end, { buffer = prev_buf, nowait = true, desc = "Agent: reject changes" })
  end

  -- Closing the preview window any other way counts as a reject.
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(prev_win),
    once = true,
    callback = function()
      finish(false)
    end,
  })

  notify(tag .. "Review diff -- ga/<CR> = apply, q/<Esc> = cancel")
end

-- Parse a multi-file response into {path, type, content} entries. The grammar
-- the system prompt produces repeats:  File: <path> / Type: patch|full / fenced
-- block. Type is inferred from the fence language (```diff -> patch) if omitted.
local function parse_entries(resp)
  local lines = vim.split(resp, "\n")
  local entries = {}
  local i = 1
  while i <= #lines do
    local path = lines[i]:match("^File:%s*(.-)%s*$")
    if path and path ~= "" then
      -- Look for an optional Type: line, then the opening fence.
      local typ
      local j = i + 1
      while j <= #lines and not lines[j]:match("^```") and not lines[j]:match("^File:") do
        typ = lines[j]:match("^Type:%s*(%w+)") or typ
        j = j + 1
      end

      local fence_lang = lines[j] and lines[j]:match("^```(%w*)")
      if fence_lang ~= nil then
        local content = {}
        local k = j + 1
        while k <= #lines and not lines[k]:match("^```%s*$") do
          content[#content + 1] = lines[k]
          k = k + 1
        end
        table.insert(entries, {
          path = path,
          type = typ or (fence_lang == "diff" and "patch" or "full"),
          content = table.concat(content, "\n"),
        })
        i = k + 1
      else
        i = j
      end
    else
      i = i + 1
    end
  end
  return entries
end

-- Compute the proposed buffer lines for one entry. Assumes the entry's file is
-- already the current buffer (patch paths read it). Returns lines or nil,err.
local function compute_entry_lines(entry)
  if entry.type == "full" then
    return vim.split(entry.content, "\n")
  end
  local lines, err
  if entry.content:match("@@") then
    lines, err = git_apply_lines(entry.content)
  end
  if not lines then
    lines, err = context_apply_lines(entry.content)
  end
  return lines, err
end

-- Apply a list of entries one at a time: open each File: target, compute the
-- proposed buffer, and preview it. Accept or reject advances to the next file.
local function apply_entries(entries)
  local n = #entries
  local function step(i)
    if i > n then
      notify(("Multi-file apply finished (%d files)"):format(n))
      return
    end

    local entry = entries[i]
    local abs = entry.path:match("^/") and entry.path or (repo_root() .. "/" .. entry.path)
    vim.cmd.edit(vim.fn.fnameescape(abs)) -- new files open as an empty buffer

    local label = ("[%d/%d] %s (%s)"):format(i, n, entry.path, entry.type)
    local lines, err = compute_entry_lines(entry)
    if not lines then
      notify(("%s skipped: %s"):format(label, err or "could not apply"), vim.log.levels.WARN)
      step(i + 1)
      return
    end

    preview_and_commit(lines, {
      label = label,
      on_done = function()
        step(i + 1)
      end,
    })
  end
  step(1)
end

function M.apply()
  local resp = vim.fn.has("clipboard") == 1 and vim.fn.getreg("+") or vim.fn.getreg('"')
  if resp == "" then
    notify("Clipboard empty", vim.log.levels.WARN)
    return
  end

  -- A <tool>…</tool> block means the model is requesting context or writing files via
  -- the tool loop -- delegate. Otherwise this is a final answer to apply.
  if resp:match("<tool") and resp:match("</tool>") then
    return M.tool()
  end

  -- 0. File:-tagged response (one or many files): apply each, honoring File:.
  local entries = parse_entries(resp)
  if #entries > 0 then
    apply_entries(entries)
    return
  end

  -- The rest handles untagged replies (a bare diff or a selection code block).

  -- 1. Try to extract from ```diff block
  local diff = extract_last_diff_block(resp)

  -- 2. If not found, treat the whole reply as a diff only if it has @@ hunks.
  if not diff then
    for _, line in ipairs(vim.split(resp, "\n")) do
      if line:match("^@@") then
        diff = resp
        break
      end
    end
  end

  -- 3. Diff: compute the proposed buffer, then preview before committing.
  if diff then
    local lines, err
    -- Prefer git apply when the diff has real @@ hunk headers (multi-hunk safe).
    if diff:match("@@") then
      lines, err = git_apply_lines(diff)
    end
    -- Headerless diff, or git apply rejected it: locate the change by context.
    if not lines then
      lines, err = context_apply_lines(diff)
    end
    if not lines then
      notify("Could not apply diff: " .. (err or "unknown error"), vim.log.levels.WARN)
      return
    end
    preview_and_commit(lines)
    return
  end

  -- 4. Code block. FORMAT 2 (Type: full) replaces the WHOLE buffer -- opening
  -- the file named in the File: header first if it isn't the current buffer.
  -- Otherwise the block replaces the current visual selection (FORMAT 1-less
  -- refactor/code flow).
  local code = extract_last_code_block(resp) or resp

  if resp:match("[Tt]ype:%s*full") then
    local file_hdr = resp:match("File:%s*([^\n\r]+)")
    if file_hdr then
      file_hdr = vim.trim(file_hdr)
      local abs = file_hdr:match("^/") and file_hdr or (repo_root() .. "/" .. file_hdr)
      if vim.fn.fnamemodify(abs, ":p") ~= vim.fn.expand("%:p") then
        vim.cmd.edit(vim.fn.fnameescape(abs))
      end
    end
    preview_and_commit(vim.split(code, "\n"))
    return
  end

  local s = vim.fn.getpos("'<")
  local e = vim.fn.getpos("'>")
  if s[2] == 0 or e[2] == 0 then
    notify("No visual selection, and no 'Type: full' header found.", vim.log.levels.WARN)
    return
  end
  preview_and_commit(selection_replaced_lines(s, e, code))
end

return M

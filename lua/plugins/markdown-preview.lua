-- Live markdown preview that opens in a new Brave window (your previous setup).
-- The lang.markdown extra handles LSP/lint/render; this adds browser preview.
return {
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    ft = { "markdown" },
    build = "cd app && npx --yes yarn install",
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }
      vim.g.mkdp_echo_preview_url = 1
      vim.g.mkdp_browserfunc = "OpenMarkdownPreview"
      vim.cmd([[
        function! OpenMarkdownPreview(url) abort
          call jobstart(['brave-browser', '--new-window', a:url], {'detach': v:true})
        endfunction
      ]])
    end,
    keys = {
      { "<leader>cm", "<cmd>MarkdownPreviewToggle<cr>", ft = "markdown", desc = "Markdown Preview (toggle)" },
    },
  },
}

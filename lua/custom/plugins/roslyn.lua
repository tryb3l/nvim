-- C# LSP, migrated from the old lazy.nvim spec at lua/kickstart/plugins/roslyn.lua
vim.pack.add {
  'https://github.com/seblyng/roslyn.nvim',
  'https://github.com/Crashdummyy/mason-registry',
}

-- roslyn.nvim only makes sense for C#/Razor buffers, so defer setup() until one is opened
vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'cs', 'razor' },
  once = true,
  callback = function()
    require('roslyn').setup {
      args = {
        '--logLevel=Information',
        '--extensionLogDirectory=' .. vim.fn.stdpath 'state' .. '/roslyn',
        '--stdio',
      },
    }
  end,
})

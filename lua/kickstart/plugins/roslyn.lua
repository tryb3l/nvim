return {
  'seblyng/roslyn.nvim',
  ft = { 'cs', 'razor' },
  dependencies = {
    { 'Crashdummyy/mason-registry' },
  },
  opts = { 
    args = {
      '--logLevel=Information',
      '--extensionLogDirectory=' .. vim.fn.stdpath('state') .. '/roslyn',
      '--stdio',
    },
  }
}

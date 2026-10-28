vim.pack.add {
  'https://github.com/stevearc/oil.nvim',
  'https://github.com/folke/flash.nvim',
  'https://github.com/windwp/nvim-ts-autotag',
  'https://github.com/nvim-treesitter/nvim-treesitter-context',
  'https://github.com/folke/trouble.nvim',
}

require('oil').setup {
  columns = vim.g.have_nerd_font and { 'icon' } or {},
  delete_to_trash = true,
  skip_confirm_for_simple_edits = false,
  watch_for_changes = false,
}
vim.keymap.set('n', '-', '<Cmd>Oil<CR>', { desc = 'Open parent directory (Oil)' })

require('flash').setup {
  modes = {
    char = { enabled = false },
    search = { enabled = false },
  },
}
vim.keymap.set({ 'n', 'x', 'o' }, '<leader>j', function() require('flash').jump() end, { desc = '[J]ump with Flash' })
vim.keymap.set({ 'n', 'x', 'o' }, '<leader>J', function() require('flash').treesitter() end, { desc = 'Select syntax with Flash' })

require('nvim-ts-autotag').setup {}

require('treesitter-context').setup {
  max_lines = 3,
  multiline_threshold = 3,
  min_window_height = 20,
  on_attach = function(buf) return vim.treesitter.highlighter.active[buf] ~= nil end,
}
vim.keymap.set('n', '<leader>tc', function() require('treesitter-context').toggle() end, { desc = '[T]oggle syntax [C]ontext' })

require('trouble').setup {}
vim.keymap.set('n', '<leader>xx', '<Cmd>Trouble diagnostics toggle<CR>', { desc = 'Workspace Diagnostics (Trouble)' })
vim.keymap.set('n', '<leader>xX', '<Cmd>Trouble diagnostics toggle filter.buf=0<CR>', { desc = 'Buffer Diagnostics (Trouble)' })
vim.keymap.set('n', '<leader>xs', '<Cmd>Trouble symbols toggle focus=false<CR>', { desc = 'Document [S]ymbols (Trouble)' })
vim.keymap.set('n', '<leader>xl', '<Cmd>Trouble lsp toggle focus=false win.position=right<CR>', { desc = '[L]SP References / Definitions (Trouble)' })
vim.keymap.set('n', '<leader>xq', '<Cmd>Trouble qflist toggle<CR>', { desc = '[Q]uickfix List (Trouble)' })

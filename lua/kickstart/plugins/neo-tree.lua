-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

---@module 'lazy'
---@type LazySpec
return {
  'nvim-neo-tree/neo-tree.nvim',
  version = '*',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-tree/nvim-web-devicons', -- not strictly required, but recommended
    'MunifTanjim/nui.nvim',
  },
  lazy = false,
  keys = {
    { '\\', ':Neotree reveal<CR>', desc = 'NeoTree reveal', silent = true },
  },
  ---@module 'neo-tree'
  ---@type neotree.Config
  opts = {
    filesystem = {
      -- NO NEED TO REFRESH MANUALLY
      use_libuv_file_watcher = true,
      -- INTELLIGENTLY FOLLOW THE CURRENT FILE
      follow_current_file = {
        enabled = true,
        leave_dirs_open = false, -- Closes other folders to keep things clean
      },
      -- RESPECT GITIGNORE
      filtered_items = {
        hide_gitignored = true,
        hide_dotfiles = false, -- Useful to see .env files
      },
      window = {
        mappings = {
          ['\\'] = 'close_window',
        },
      },
    },
    enable_global_clipboard = true,
  },
}

vim.pack.add {
  'https://github.com/seblyng/roslyn.nvim',
  'https://github.com/mfussenegger/nvim-dap',
}
require('roslyn').setup {}

local dap = require 'dap'
local netcoredbg_bin = vim.fn.stdpath 'data' .. '/mason/bin/netcoredbg'

dap.adapters.coreclr = {
  type = 'executable',
  command = vim.fn.executable(netcoredbg_bin) == 1 and netcoredbg_bin or 'netcoredbg',
  args = { '--interpreter=vscode' },
}

local function pick_dotnet_dll()
  local cwd = vim.fn.getcwd()
  local dlls = vim.fn.glob(cwd .. '/**/bin/Debug/**/*.dll', false, true)
  local default_dll = dlls[1] or (cwd .. '/bin/Debug/')
  return vim.fn.input('Path to .dll to debug: ', default_dll, 'file')
end

dap.configurations.cs = {
  {
    type = 'coreclr',
    name = 'Launch .NET Project (netcoredbg)',
    request = 'launch',
    program = pick_dotnet_dll,
    cwd = '${workspaceFolder}',
  },
  {
    type = 'coreclr',
    name = 'Attach to .NET Process (netcoredbg)',
    request = 'attach',
    processId = require('dap.utils').pick_process,
  },
}

-- JS/TS debugging, migrated from the old lazy.nvim spec at lua/kickstart/plugins/js-debug.lua
-- vscode-js-debug's build step (npm install + gulp bundle) is handled by the
-- PackChanged autocmd in Section 3 of init.lua.
vim.pack.add {
  'https://github.com/mfussenegger/nvim-dap',
  'https://github.com/mxsdev/nvim-dap-vscode-js',
  { src = 'https://github.com/microsoft/vscode-js-debug', version = 'v1.76.1' },
}

require('dap-vscode-js').setup {
  debugger_path = vim.fn.stdpath 'data' .. '/site/pack/core/opt/vscode-js-debug',
  adapters = { 'pwa-node', 'pwa-chrome', 'pwa-msedge', 'node-terminal', 'pwa-extensionHost' },
}

local dap = require 'dap'
for _, language in ipairs { 'typescript', 'javascript', 'typescriptreact', 'javascriptreact' } do
  dap.configurations[language] = {
    -- Debug React/Angular via Chrome
    {
      type = 'pwa-chrome',
      request = 'launch',
      name = 'Launch Chrome (Client-side)',
      url = 'http://localhost:3000',
      webRoot = '${workspaceFolder}',
      sourceMaps = true,
    },
    -- Debug Playwright Tests
    {
      type = 'pwa-node',
      request = 'launch',
      name = 'Debug Playwright Tests',
      runtimeExecutable = 'npx',
      runtimeArgs = { 'playwright', 'test' },
      rootPath = '${workspaceFolder}',
      cwd = '${workspaceFolder}',
      console = 'integratedTerminal',
      internalConsoleOptions = 'neverOpen',
    },
    -- Attach to a running Node API/Backend
    {
      type = 'pwa-node',
      request = 'attach',
      name = 'Attach to Node Backend',
      processId = require('dap.utils').pick_process,
      cwd = '${workspaceFolder}',
    },
  }
end

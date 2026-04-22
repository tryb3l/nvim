return {
  'mfussenegger/nvim-dap',
  dependencies = {
    'mxsdev/nvim-dap-vscode-js',
    {
      'microsoft/vscode-js-debug',
      -- This build string installs dependencies and then "undos" changes to package-lock.json
      -- so that Git (and Lazy.nvim) sees the directory as clean.
         version = '1.76.1',
         build = "npm install --legacy-peer-deps && npx gulp vsDebugServerBundle && mv dist out", 
    },
  },

  config = function()
    --- Added to shut LSP's noise for that block.
    ---@diagnostic disable-next-line: missing-fields, assign-type-mismatch
    require('dap-vscode-js').setup {
      debugger_path = vim.fn.stdpath 'data' .. '/lazy/vscode-js-debug',
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
  end,
}

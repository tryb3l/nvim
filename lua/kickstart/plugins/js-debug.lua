return {
  'mfussenegger/nvim-dap',
  dependencies = {
    'mxsdev/nvim-dap-vscode-js',
    {
      "microsoft/vscode-js-debug",
      build = "npm install --legacy-peer-deps && npx gulp vsDebugServerBundle && mv dist out" 
    }
  },
  config = function()
    require("dap-vscode-js").setup({
      debugger_path = vim.fn.stdpath("data") .. "/lazy/vscode-js-debug",
      adapters = { 'pwa-node', 'pwa-chrome', 'pwa-msedge', 'node-terminal', 'pwa-extensionHost' },
    })

    local dap = require("dap")
    for _, language in ipairs({ "typescript", "javascript", "typescriptreact", "javascriptreact" }) do
      dap.configurations[language] = {
        -- Debug React/Angular via Chrome
        {
          type = "pwa-chrome",
          request = "launch",
          name = "Launch Chrome (Client-side)",
          url = "http://localhost:3000", -- Change to 4200 if using standard Angular
          webRoot = "${workspaceFolder}",
          sourceMaps = true,
        },
        -- Debug Playwright Tests
        {
          type = "pwa-node",
          request = "launch",
          name = "Debug Playwright Tests",
          runtimeExecutable = "npx",
          runtimeArgs = { "playwright", "test" },
          rootPath = "${workspaceFolder}",
          cwd = "${workspaceFolder}",
          console = "integratedTerminal",
          internalConsoleOptions = "neverOpen",
        },
        -- Attach to a running Node API/Backend
        {
          type = "pwa-node",
          request = "attach",
          name = "Attach to Node Backend",
          processId = require('dap.utils').pick_process,
          cwd = "${workspaceFolder}",
        }
      }
    end
  end
}

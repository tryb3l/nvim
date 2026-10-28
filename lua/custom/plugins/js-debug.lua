vim.pack.add { 'https://github.com/mfussenegger/nvim-dap' }
local dap = require 'dap'
for _, adapter in ipairs { 'pwa-node', 'pwa-chrome', 'pwa-msedge', 'node-terminal', 'pwa-extensionHost' } do
  dap.adapters[adapter] = {
    type = 'server',
    host = '127.0.0.1',
    port = '${port}',
    executable = {
      command = 'js-debug-adapter',
      args = { '${port}', '127.0.0.1' },
    },
  }
end

for _, language in ipairs { 'typescript', 'javascript', 'typescriptreact', 'javascriptreact' } do
  dap.configurations[language] = {
    -- Launch current Fastify / Node / TS file directly
    {
      type = 'pwa-node',
      request = 'launch',
      name = 'Launch Current File (Node / TS)',
      program = '${file}',
      cwd = '${workspaceFolder}',
      sourceMaps = true,
      console = 'integratedTerminal',
      internalConsoleOptions = 'neverOpen',
    },
    -- Launch Fastify / Backend via npm run dev
    {
      type = 'pwa-node',
      request = 'launch',
      name = 'Launch npm run dev (Fastify / Backend)',
      runtimeExecutable = 'npm',
      runtimeArgs = { 'run', 'dev' },
      cwd = '${workspaceFolder}',
      sourceMaps = true,
      console = 'integratedTerminal',
      internalConsoleOptions = 'neverOpen',
    },
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
      runtimeExecutable = 'node',
      program = '${workspaceFolder}/node_modules/@playwright/test/cli.js',
      args = { 'test', '--workers=1', '--timeout=0' },
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

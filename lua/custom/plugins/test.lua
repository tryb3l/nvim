local ns = vim.api.nvim_create_namespace 'custom-test-status'
local last_run = nil
local term_buf = nil
local term_win = nil

local function find_root(bufnr)
  local markers = { 'playwright.config.ts', 'playwright.config.js', 'package.json', 'go.mod', '.git' }
  return vim.fs.root(bufnr, markers) or vim.fn.getcwd()
end

local function is_playwright_buf(bufnr, root)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, math.min(vim.api.nvim_buf_line_count(bufnr), 80), false)
  for _, line in ipairs(lines) do
    if line:find('node:test', 1, true) then return false end
    if line:find('@playwright/test', 1, true) then return true end
  end
  return vim.uv.fs_stat(root .. '/node_modules/@playwright/test') ~= nil
    and (vim.uv.fs_stat(root .. '/playwright.config.ts') ~= nil or vim.uv.fs_stat(root .. '/playwright.config.js') ~= nil)
end

local function escape_regex(str) return (str:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])', '\\%1')) end

-- Extract nearest test name and 1-based line number using Neovim's built-in Treesitter
local function find_nearest_test(bufnr)
  local ft = vim.bo[bufnr].filetype
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  pcall(function() vim.treesitter.get_parser(bufnr):parse() end)
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = { row, cursor[2] } })
  if not ok or not node then return nil, cursor[1] end

  if ft == 'javascript' or ft == 'typescript' or ft == 'javascriptreact' or ft == 'typescriptreact' then
    while node do
      if node:type() == 'call_expression' then
        local fn_node = node:field('function')[1]
        local args_node = node:field('arguments')[1]
        if fn_node and args_node then
          local fn_text = vim.treesitter.get_node_text(fn_node, bufnr)
          if
            fn_text:match '^test$'
            or fn_text:match '^it$'
            or fn_text:match '^describe$'
            or fn_text:match '^test%.'
            or fn_text:match '^it%.'
            or fn_text:match '^describe%.'
          then
            for child in args_node:iter_children() do
              local ctype = child:type()
              if ctype == 'string' or ctype == 'template_string' then
                local raw = vim.treesitter.get_node_text(child, bufnr)
                local name = raw:sub(2, -2)
                local start_row = node:range()
                return name, start_row + 1
              end
            end
          end
        end
      end
      node = node:parent()
    end
  elseif ft == 'go' then
    while node do
      if node:type() == 'function_declaration' then
        local name_node = node:field('name')[1]
        if name_node then
          local name = vim.treesitter.get_node_text(name_node, bufnr)
          if name:match '^Test' or name:match '^Benchmark' then
            local start_row = node:range()
            return name, start_row + 1
          end
        end
      end
      node = node:parent()
    end
  elseif ft == 'cs' then
    while node do
      if node:type() == 'method_declaration' then
        local name_node = node:field('name')[1]
        if name_node then
          local name = vim.treesitter.get_node_text(name_node, bufnr)
          local start_row = node:range()
          return name, start_row + 1
        end
      end
      node = node:parent()
    end
  end

  return nil, cursor[1]
end

local function set_badge(bufnr, line, text, hl)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  local target_line = math.max(0, math.min((line or 1) - 1, vim.api.nvim_buf_line_count(bufnr) - 1))
  vim.api.nvim_buf_set_extmark(bufnr, ns, target_line, 0, {
    virt_text = { { '  ' .. text, hl } },
    virt_text_pos = 'eol',
  })
end

local function open_test_Output_win()
  if term_win and vim.api.nvim_win_is_valid(term_win) then return term_win end
  local prev_win = vim.api.nvim_get_current_win()
  vim.cmd 'botright 14split'
  term_win = vim.api.nvim_get_current_win()
  vim.wo[term_win].number = false
  vim.wo[term_win].relativenumber = false
  vim.wo[term_win].signcolumn = 'no'
  if term_buf and vim.api.nvim_buf_is_valid(term_buf) then vim.api.nvim_win_set_buf(term_win, term_buf) end
  vim.api.nvim_set_current_win(prev_win)
  return term_win
end

local function execute_test(spec)
  last_run = spec
  local prev_win = vim.api.nvim_get_current_win()
  set_badge(spec.bufnr, spec.line, '⏳ running: ' .. spec.label, 'DiagnosticInfo')

  open_test_Output_win()
  vim.api.nvim_set_current_win(term_win)

  local prev_buf = term_buf
  term_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(term_win, term_buf)
  if prev_buf and vim.api.nvim_buf_is_valid(prev_buf) then pcall(vim.api.nvim_buf_delete, prev_buf, { force = true }) end

  vim.keymap.set('n', 'q', function()
    if term_win and vim.api.nvim_win_is_valid(term_win) then vim.api.nvim_win_close(term_win, true) end
  end, { buffer = term_buf, silent = true, desc = 'Close test output window' })

  vim.fn.jobstart(spec.cmd, {
    cwd = spec.cwd,
    term = true,
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          set_badge(spec.bufnr, spec.line, '✓ passed: ' .. spec.label, 'DiagnosticOk')
        else
          set_badge(spec.bufnr, spec.line, '✗ failed (' .. code .. '): ' .. spec.label, 'DiagnosticError')
        end
      end)
    end,
  })

  vim.cmd 'normal! G'
  if vim.api.nvim_win_is_valid(prev_win) then vim.api.nvim_set_current_win(prev_win) end
end

local function build_spec(scope, extra_opts)
  extra_opts = extra_opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(bufnr)
  local ft = vim.bo[bufnr].filetype
  local root = find_root(bufnr)
  local rel_file = vim.fs.relpath(root, file) or file
  local test_name, line = find_nearest_test(bufnr)
  local target_line = (scope == 'nearest') and line or 1

  if ft == 'javascript' or ft == 'typescript' or ft == 'javascriptreact' or ft == 'typescriptreact' then
    if is_playwright_buf(bufnr, root) then
      local pw_bin = vim.uv.fs_stat(root .. '/node_modules/.bin/playwright') and (root .. '/node_modules/.bin/playwright') or 'npx'
      local cmd = (pw_bin == 'npx') and { 'npx', 'playwright', 'test' } or { pw_bin, 'test' }
      local target = (scope == 'nearest') and (rel_file .. ':' .. line) or rel_file
      table.insert(cmd, target)
      if extra_opts.headed then table.insert(cmd, '--headed') end
      return {
        kind = 'playwright',
        cmd = cmd,
        cwd = root,
        bufnr = bufnr,
        file = file,
        rel_file = rel_file,
        line = target_line,
        test_name = test_name,
        label = (scope == 'nearest' and test_name) and ('Playwright: ' .. test_name) or ('Playwright: ' .. vim.fn.fnamemodify(file, ':t')),
      }
    else
      local cmd = { 'node', '--test' }
      if scope == 'nearest' and test_name then table.insert(cmd, '--test-name-pattern=' .. escape_regex(test_name)) end
      table.insert(cmd, rel_file)
      return {
        kind = 'node',
        cmd = cmd,
        cwd = root,
        bufnr = bufnr,
        file = file,
        rel_file = rel_file,
        line = target_line,
        test_name = test_name,
        label = (scope == 'nearest' and test_name) and ('node:test: ' .. test_name) or ('node:test: ' .. vim.fn.fnamemodify(file, ':t')),
      }
    end
  elseif ft == 'go' then
    local pkg_dir = './' .. (vim.fs.relpath(root, vim.fn.fnamemodify(file, ':h')) or '.')
    local cmd = { 'go', 'test', '-v' }
    if scope == 'nearest' and test_name then vim.list_extend(cmd, { '-run', '^' .. test_name .. '$' }) end
    table.insert(cmd, pkg_dir)
    return {
      kind = 'go',
      cmd = cmd,
      cwd = root,
      bufnr = bufnr,
      file = file,
      line = target_line,
      test_name = test_name,
      label = (scope == 'nearest' and test_name) and ('go test: ' .. test_name) or ('go test: ' .. pkg_dir),
    }
  elseif ft == 'cs' then
    local cmd = { 'dotnet', 'test' }
    if scope == 'nearest' and test_name then vim.list_extend(cmd, { '--filter', 'Name~' .. test_name }) end
    return {
      kind = 'cs',
      cmd = cmd,
      cwd = root,
      bufnr = bufnr,
      file = file,
      line = target_line,
      test_name = test_name,
      label = (scope == 'nearest' and test_name) and ('dotnet test: ' .. test_name) or 'dotnet test',
    }
  end

  vim.notify('No test runner configured for filetype: ' .. ft, vim.log.levels.WARN)
  return nil
end

local function debug_nearest()
  local spec = build_spec 'nearest'
  if not spec then return end
  if spec.kind == 'go' then
    require('dap-go').debug_test()
    return
  end
  local dap = require 'dap'
  if spec.kind == 'playwright' then
    local target = (spec.test_name and (spec.rel_file .. ':' .. spec.line)) or spec.rel_file
    dap.run {
      type = 'pwa-node',
      request = 'launch',
      name = 'Debug ' .. spec.label,
      runtimeExecutable = 'node',
      program = spec.cwd .. '/node_modules/@playwright/test/cli.js',
      args = { 'test', target, '--workers=1', '--timeout=0' },
      cwd = spec.cwd,
      console = 'integratedTerminal',
      internalConsoleOptions = 'neverOpen',
    }
  elseif spec.kind == 'node' then
    local runtime_args = { '--test' }
    if spec.test_name then table.insert(runtime_args, '--test-name-pattern=' .. escape_regex(spec.test_name)) end
    table.insert(runtime_args, spec.file)
    dap.run {
      type = 'pwa-node',
      request = 'launch',
      name = 'Debug ' .. spec.label,
      runtimeExecutable = 'node',
      runtimeArgs = runtime_args,
      cwd = spec.cwd,
      console = 'integratedTerminal',
      internalConsoleOptions = 'neverOpen',
    }
  else
    vim.notify('Debug nearest test is supported for Playwright, node:test, and Go.', vim.log.levels.INFO)
  end
end

vim.keymap.set('n', '<leader>tn', function()
  local spec = build_spec 'nearest'
  if spec then execute_test(spec) end
end, { desc = '[T]est [N]earest under cursor' })

vim.keymap.set('n', '<leader>tf', function()
  local spec = build_spec 'file'
  if spec then execute_test(spec) end
end, { desc = '[T]est current [F]ile' })

vim.keymap.set('n', '<leader>td', debug_nearest, { desc = '[T]est [D]ebug nearest with breakpoints' })

vim.keymap.set('n', '<leader>tl', function()
  if last_run then
    execute_test(last_run)
  else
    vim.notify('No previous test run in this session.', vim.log.levels.INFO)
  end
end, { desc = '[T]est re-run [L]ast' })

vim.keymap.set('n', '<leader>tp', function()
  local spec = build_spec('nearest', { headed = true })
  if spec then execute_test(spec) end
end, { desc = '[T]est [P]laywright headed (watch browser)' })

vim.keymap.set('n', '<leader>to', function()
  if term_win and vim.api.nvim_win_is_valid(term_win) then
    vim.api.nvim_win_close(term_win, true)
    term_win = nil
  elseif term_buf and vim.api.nvim_buf_is_valid(term_buf) then
    open_test_Output_win()
  else
    vim.notify('No test output yet.', vim.log.levels.INFO)
  end
end, { desc = '[T]est toggle [O]utput window' })

return {
  build_spec = build_spec,
  find_nearest_test = find_nearest_test,
}

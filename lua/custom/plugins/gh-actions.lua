local gh_win = nil
local gh_buf = nil

local function find_git_root() return vim.fs.root(0, { '.git' }) or vim.fn.getcwd() end

local function open_gh_float(title, cmd, cwd)
  if gh_win and vim.api.nvim_win_is_valid(gh_win) then vim.api.nvim_win_close(gh_win, true) end

  gh_buf = vim.api.nvim_create_buf(false, true)
  local width = math.floor(vim.o.columns * 0.84)
  local height = math.floor(vim.o.lines * 0.80)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  gh_win = vim.api.nvim_open_win(gh_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. title .. ' (press q to close) ',
    title_pos = 'center',
  })

  vim.keymap.set('n', 'q', function()
    if gh_win and vim.api.nvim_win_is_valid(gh_win) then
      vim.api.nvim_win_close(gh_win, true)
      gh_win = nil
    end
  end, { buffer = gh_buf, silent = true, desc = 'Close GitHub Actions window' })

  vim.fn.jobstart(cmd, {
    cwd = cwd,
    term = true,
  })
end

local function watch_latest_run()
  local cwd = find_git_root()
  vim.system(
    { 'gh', 'run', 'list', '--limit', '1', '--json', 'databaseId,status,conclusion,workflowName,displayTitle,headBranch' },
    { cwd = cwd, text = true },
    function(res)
      vim.schedule(function()
        if res.code ~= 0 or not res.stdout then
          vim.notify('gh run list failed: ' .. (res.stderr or ''), vim.log.levels.WARN)
          return
        end
        local ok, runs = pcall(vim.json.decode, res.stdout)
        if not ok or type(runs) ~= 'table' or #runs == 0 then
          vim.notify('No GitHub Actions workflow runs found for this repo.', vim.log.levels.INFO)
          return
        end
        local run = runs[1]
        local id = tostring(run.databaseId)
        local title = string.format('GitHub Actions: %s (%s)', run.workflowName or 'Workflow', run.headBranch or '')
        if run.status == 'in_progress' or run.status == 'queued' or run.status == 'waiting' then
          open_gh_float(title, { 'gh', 'run', 'watch', id }, cwd)
        elseif run.conclusion == 'failure' then
          open_gh_float(title .. ' [FAILED]', { 'gh', 'run', 'view', id, '--log-failed' }, cwd)
        else
          open_gh_float(title, { 'gh', 'run', 'view', id }, cwd)
        end
      end)
    end
  )
end

local function pick_workflow_runs()
  local cwd = find_git_root()
  vim.system({
    'gh',
    'run',
    'list',
    '--limit',
    '25',
    '--json',
    'databaseId,status,conclusion,workflowName,displayTitle,headBranch,createdAt,event',
  }, { cwd = cwd, text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 or not res.stdout then
        vim.notify('gh run list failed: ' .. (res.stderr or ''), vim.log.levels.WARN)
        return
      end
      local ok, runs = pcall(vim.json.decode, res.stdout)
      if not ok or type(runs) ~= 'table' or #runs == 0 then
        vim.notify('No GitHub Actions workflow runs found for this repo.', vim.log.levels.INFO)
        return
      end

      local pickers = require 'telescope.pickers'
      local finders = require 'telescope.finders'
      local conf = require('telescope.config').values
      local actions = require 'telescope.actions'
      local action_state = require 'telescope.actions.state'

      local function icon_for(run)
        if run.status ~= 'completed' then return '⏳ ' .. (run.status or 'running') end
        if run.conclusion == 'success' then return '✓ success' end
        if run.conclusion == 'failure' then return '✗ failure' end
        return '• ' .. (run.conclusion or 'done')
      end

      pickers
        .new({}, {
          prompt_title = 'GitHub Actions Runs (Enter: view/logs, <C-w>: watch live, <C-o>: open browser)',
          finder = finders.new_table {
            results = runs,
            entry_maker = function(run)
              local badge = icon_for(run)
              local display =
                string.format('%-12s │ %-20s │ %-16s │ %s', badge, run.workflowName or 'Workflow', run.headBranch or '', run.displayTitle or '')
              return {
                value = run,
                display = display,
                ordinal = table.concat({
                  badge,
                  run.workflowName or '',
                  run.headBranch or '',
                  run.displayTitle or '',
                }, ' '),
              }
            end,
          },
          sorter = conf.generic_sorter {},
          attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
              actions.close(prompt_bufnr)
              local selection = action_state.get_selected_entry()
              if not selection then return end
              local run = selection.value
              local id = tostring(run.databaseId)
              local title = string.format('%s #%s', run.workflowName or 'Run', id)
              if run.status ~= 'completed' then
                open_gh_float(title, { 'gh', 'run', 'watch', id }, cwd)
              elseif run.conclusion == 'failure' then
                open_gh_float(title .. ' [Failed Logs]', { 'gh', 'run', 'view', id, '--log-failed' }, cwd)
              else
                open_gh_float(title, { 'gh', 'run', 'view', id }, cwd)
              end
            end)

            map({ 'i', 'n' }, '<C-w>', function()
              actions.close(prompt_bufnr)
              local selection = action_state.get_selected_entry()
              if not selection then return end
              local run = selection.value
              local id = tostring(run.databaseId)
              open_gh_float('Watch ' .. (run.workflowName or 'Run'), { 'gh', 'run', 'watch', id }, cwd)
            end)

            map({ 'i', 'n' }, '<C-o>', function()
              actions.close(prompt_bufnr)
              local selection = action_state.get_selected_entry()
              if not selection then return end
              vim.system({ 'gh', 'run', 'view', tostring(selection.value.databaseId), '--web' }, { cwd = cwd })
            end)

            return true
          end,
        })
        :find()
    end)
  end)
end

vim.keymap.set('n', '<leader>gw', watch_latest_run, { desc = '[G]itHub Actions: [W]atch latest/active run' })
vim.keymap.set('n', '<leader>gr', pick_workflow_runs, { desc = '[G]itHub Actions: Pick [R]uns (Telescope)' })

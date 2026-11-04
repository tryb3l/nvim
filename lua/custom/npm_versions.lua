local source = {}
local cache = {}
local inflight = {}
local ns = vim.api.nvim_create_namespace 'npm_versions_virt'
local enabled_state = true

local DEP_KEYS = {
  dependencies = true,
  devDependencies = true,
  peerDependencies = true,
  optionalDependencies = true,
  overrides = true,
  resolutions = true,
  catalog = true,
}

function source.new() return setmetatable({}, { __index = source }) end

function source:enabled() return vim.fn.expand '%:t' == 'package.json' end

function source:get_trigger_characters() return { '"', '^', '~', '.' } end

local function is_valid_pkg_name(pkg)
  if not pkg or #pkg == 0 or #pkg > 214 then return false end
  if pkg:sub(1, 1) == '.' or pkg:sub(1, 1) == '_' or pkg:sub(1, 1) == '-' then return false end
  return pkg:match '^@?[a-z0-9-~][a-z0-9-._~]*/?[a-z0-9-._~]*$' ~= nil
end

local function in_dependencies_block(bufnr, row)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, row, false)
  local depth = 0
  for i = #lines, 1, -1 do
    local line = lines[i]
    for ch in line:gmatch '[{}]' do
      depth = depth + (ch == '}' and 1 or -1)
    end
    if depth < 0 then
      local key = line:match '^%s*"([^"]+)"%s*:%s*{%s*$'
      if key and DEP_KEYS[key] then return true end
    end
  end
  return false
end

local function parse_semver(str)
  if not str then return nil end
  local prefix, maj, min, pat, rest = str:match '^([%^~>=<]*)%s*(%d+)%.(%d+)%.(%d+)(.*)$'
  if not maj then return nil end
  return {
    prefix = prefix or '',
    maj = tonumber(maj),
    min = tonumber(min),
    pat = tonumber(pat),
    rest = rest or '',
    ver = string.format('%d.%d.%d', tonumber(maj), tonumber(min), tonumber(pat)),
  }
end

local function cmp_semver(a, b)
  if a.maj ~= b.maj then return a.maj > b.maj end
  if a.min ~= b.min then return a.min > b.min end
  return a.pat > b.pat
end

local function parse_versions(raw)
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= 'table' or type(decoded.versions) ~= 'table' then return nil end
  local latest = type(decoded['dist-tags']) == 'table' and decoded['dist-tags'].latest or nil
  local list = {}
  for ver in pairs(decoded.versions) do
    local maj, min, pat = ver:match '^(%d+)%.(%d+)%.(%d+)$'
    if maj then
      list[#list + 1] = { ver = ver, maj = tonumber(maj), min = tonumber(min), pat = tonumber(pat) }
    end
  end
  table.sort(list, cmp_semver)
  local versions = {}
  if latest then versions[#versions + 1] = latest end
  for i = 1, #list do
    if list[i].ver ~= latest then versions[#versions + 1] = list[i].ver end
  end
  return { latest = latest or (list[1] and list[1].ver) or nil, versions = versions, parsed_list = list }
end

local function fetch_package(pkg, cb)
  if not is_valid_pkg_name(pkg) then
    cb(nil)
    return nil
  end
  if cache[pkg] then
    cb(cache[pkg])
    return nil
  end
  if inflight[pkg] then
    table.insert(inflight[pkg].callbacks, cb)
    return inflight[pkg].job
  end

  inflight[pkg] = { callbacks = { cb }, job = nil }
  local job = vim.system({
    'curl',
    '-fsSL',
    '--max-time',
    '4',
    '-H',
    'Accept: application/vnd.npm.install-v1+json',
    '--',
    'https://registry.npmjs.org/' .. pkg,
  }, { text = true }, function(res)
    local parsed = (res.code == 0 and res.stdout) and parse_versions(res.stdout) or nil
    if parsed then cache[pkg] = parsed end
    local entry = inflight[pkg]
    inflight[pkg] = nil
    vim.schedule(function()
      if entry then
        for _, fn in ipairs(entry.callbacks) do
          fn(parsed)
        end
      end
    end)
  end)
  inflight[pkg].job = job
  return job
end

local function compute_updates(data, current_spec)
  local cur = parse_semver(current_spec)
  if not cur or cur.rest ~= '' or not data or not data.parsed_list then return nil end

  local latest_ver = data.latest
  local latest_sv = parse_semver(latest_ver)
  local compat_ver = nil

  for _, item in ipairs(data.parsed_list) do
    if cur.prefix == '~' then
      if item.maj == cur.maj and item.min == cur.min and cmp_semver(item, cur) then
        compat_ver = item.ver
        break
      end
    else
      -- Default / '^': highest version within the same major (or same minor when major is 0)
      local same_compat = (cur.maj > 0 and item.maj == cur.maj) or (cur.maj == 0 and item.maj == 0 and item.min == cur.min)
      if same_compat and cmp_semver(item, cur) then
        compat_ver = item.ver
        break
      end
    end
  end

  local has_major = latest_sv and cmp_semver(latest_sv, cur) and latest_ver ~= compat_ver
  if not compat_ver and not has_major then return nil end

  return {
    prefix = (cur.prefix == '^' or cur.prefix == '~') and cur.prefix or '^',
    compat = compat_ver,
    latest = has_major and latest_ver or nil,
    target_latest = latest_ver or compat_ver,
  }
end

local function extract_buffer_deps(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local deps = {}
  local in_dep_section = false
  local section_depth = 0
  local depth = 0

  for idx, line in ipairs(lines) do
    if not in_dep_section then
      local key = line:match '^%s*"([^"]+)"%s*:%s*{%s*$'
      if key and DEP_KEYS[key] then
        in_dep_section = true
        section_depth = depth
      end
    end

    for ch in line:gmatch '[{}]' do
      depth = depth + (ch == '{' and 1 or -1)
    end

    if in_dep_section then
      if depth <= section_depth then
        in_dep_section = false
      else
        local pkg, spec = line:match '^%s*"([^"]+)"%s*:%s*"([^"]+)"'
        if pkg and spec and is_valid_pkg_name(pkg) and parse_semver(spec) then
          deps[#deps + 1] = { lnum = idx - 1, pkg = pkg, spec = spec }
        end
      end
    end
  end
  return deps
end

local function render_dep_extmark(bufnr, dep, data)
  if not enabled_state or not vim.api.nvim_buf_is_valid(bufnr) then return end
  local info = compute_updates(data, dep.spec)
  if not info then return end

  local chunks = {}
  if info.compat and info.latest then
    chunks[#chunks + 1] = { string.format('  ⬆ %s (compatible)', info.compat), 'DiagnosticInfo' }
    chunks[#chunks + 1] = { string.format(' · %s (major)', info.latest), 'DiagnosticWarn' }
  elseif info.compat then
    chunks[#chunks + 1] = { string.format('  ⬆ %s', info.compat), 'DiagnosticInfo' }
  elseif info.latest then
    chunks[#chunks + 1] = { string.format('  ⬆ %s (major)', info.latest), 'DiagnosticWarn' }
  end

  if #chunks > 0 then
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, dep.lnum, 0, {
      id = dep.lnum + 1,
      virt_text = chunks,
      virt_text_pos = 'eol',
      hl_mode = 'combine',
    })
  end
end

function source.annotate_buffer(bufnr, force_refresh)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  if vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':t') ~= 'package.json' then return end

  if force_refresh then cache = {} end
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  if not enabled_state then return end

  local deps = extract_buffer_deps(bufnr)
  if #deps == 0 then return end

  local max_concurrent = 8
  local running = 0
  local idx = 1

  local function pump()
    while running < max_concurrent and idx <= #deps do
      local dep = deps[idx]
      idx = idx + 1
      if cache[dep.pkg] then
        render_dep_extmark(bufnr, dep, cache[dep.pkg])
      else
        running = running + 1
        fetch_package(dep.pkg, function(data)
          running = running - 1
          if data then render_dep_extmark(bufnr, dep, data) end
          pump()
        end)
      end
    end
  end

  pump()
end

function source.bump_line(use_major)
  local bufnr = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  if not in_dependencies_block(bufnr, row) then return end

  local line = vim.api.nvim_get_current_line()
  local pkg, spec = line:match '^%s*"([^"]+)"%s*:%s*"([^"]+)"'
  if not pkg or not spec then return end

  fetch_package(pkg, function(data)
    if not data or not vim.api.nvim_buf_is_valid(bufnr) then return end
    local info = compute_updates(data, spec)
    if not info then
      vim.notify(string.format('%s is already up to date (%s)', pkg, spec), vim.log.levels.INFO)
      return
    end
    local target = use_major and (info.latest or info.compat) or (info.compat or info.latest)
    if not target then return end
    local cur = parse_semver(spec)
    local prefix = cur and cur.prefix or '^'
    local new_spec = prefix .. target
    local updated_line = line:gsub('(:%s*")[^"]+(")', '%1' .. new_spec .. '%2', 1)
    vim.api.nvim_buf_set_lines(bufnr, row - 1, row, false, { updated_line })
    source.annotate_buffer(bufnr, false)
  end)
end

function source.toggle()
  enabled_state = not enabled_state
  local bufnr = vim.api.nvim_get_current_buf()
  source.annotate_buffer(bufnr, false)
end

local function build_items(data, typed, row, start_col, end_col)
  local prefix = typed:match '^[%^~]' or '^'
  local ver_query = typed:gsub('^[%^~]', '')
  local kind = require('blink.cmp.types').CompletionItemKind.Value
  local range = {
    start = { line = row - 1, character = start_col },
    ['end'] = { line = row - 1, character = end_col },
  }
  local items = {}
  for _, ver in ipairs(data.versions) do
    if ver_query == '' or vim.startswith(ver, ver_query) then
      local rank = #items + 1
      local text = prefix .. ver
      items[#items + 1] = {
        label = text,
        filterText = text,
        detail = (ver == data.latest) and 'latest' or nil,
        kind = kind,
        score_offset = 1000 - rank,
        textEdit = { newText = text, range = range },
      }
      if rank == 1 and typed == '' then
        items[#items + 1] = {
          label = ver,
          filterText = ver,
          detail = (ver == data.latest) and 'exact latest' or 'exact',
          kind = kind,
          score_offset = 999 - rank,
          textEdit = { newText = ver, range = range },
        }
      end
      if #items >= 40 then break end
    end
  end
  return items
end

function source:get_completions(ctx, callback)
  local row, col = ctx.cursor[1], ctx.cursor[2]
  local before = ctx.line:sub(1, col)
  local pkg, typed = before:match '^%s*"([^"]+)"%s*:%s*"([^"]*)$'
  if not pkg or not in_dependencies_block(0, row) or not is_valid_pkg_name(pkg) then
    callback { items = {}, is_incomplete_forward = false, is_incomplete_backward = false }
    return
  end

  local start_col = col - #typed
  local after_inside = ctx.line:sub(col + 1):match '^([^"]*)"' or ''
  local end_col = col + #after_inside

  if cache[pkg] then
    callback {
      items = build_items(cache[pkg], typed, row, start_col, end_col),
      is_incomplete_forward = true,
      is_incomplete_backward = true,
    }
    return
  end

  local job = fetch_package(pkg, function(parsed)
    callback {
      items = parsed and build_items(parsed, typed, row, start_col, end_col) or {},
      is_incomplete_forward = true,
      is_incomplete_backward = true,
    }
  end)

  return function()
    if job then pcall(function() job:kill(9) end) end
  end
end

function source.setup()
  local group = vim.api.nvim_create_augroup('custom_npm_versions', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
    group = group,
    pattern = 'package.json',
    callback = function(ev)
      source.annotate_buffer(ev.buf, false)
    end,
  })

  vim.api.nvim_create_autocmd('BufReadPost', {
    group = group,
    pattern = 'package.json',
    callback = function(ev)
      vim.keymap.set('n', '<leader>pu', function() source.bump_line(false) end, {
        buffer = ev.buf,
        desc = 'npm: [U]pdate package on line (compatible)',
      })
      vim.keymap.set('n', '<leader>pU', function() source.bump_line(true) end, {
        buffer = ev.buf,
        desc = 'npm: [U]pdate package on line (latest major)',
      })
      vim.keymap.set('n', '<leader>pr', function() source.annotate_buffer(ev.buf, true) end, {
        buffer = ev.buf,
        desc = 'npm: [R]efresh package versions',
      })
      vim.keymap.set('n', '<leader>pt', function() source.toggle() end, {
        buffer = ev.buf,
        desc = 'npm: [T]oggle inline version hints',
      })
    end,
  })
end

return source

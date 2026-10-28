local source = {}
local cache = {}

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

local function in_dependencies_block(row)
  local lines = vim.api.nvim_buf_get_lines(0, 0, row, false)
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

local function parse_versions(raw)
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= 'table' or type(decoded.versions) ~= 'table' then return nil end
  local latest = type(decoded['dist-tags']) == 'table' and decoded['dist-tags'].latest or nil
  local list = {}
  for ver in pairs(decoded.versions) do
    local maj, min, pat = ver:match '^(%d+)%.(%d+)%.(%d+)$'
    if maj then list[#list + 1] = { ver = ver, maj = tonumber(maj), min = tonumber(min), pat = tonumber(pat) } end
  end
  table.sort(list, function(a, b)
    if a.maj ~= b.maj then return a.maj > b.maj end
    if a.min ~= b.min then return a.min > b.min end
    return a.pat > b.pat
  end)
  local versions = {}
  if latest then versions[#versions + 1] = latest end
  for i = 1, #list do
    if list[i].ver ~= latest then versions[#versions + 1] = list[i].ver end
  end
  return { latest = latest, versions = versions }
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
  if not pkg or not in_dependencies_block(row) then
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

  local job = vim.system({
    'curl',
    '-fsSL',
    '--max-time',
    '4',
    '-H',
    'Accept: application/vnd.npm.install-v1+json',
    'https://registry.npmjs.org/' .. pkg,
  }, { text = true }, function(res)
    if res.code ~= 0 or not res.stdout then
      vim.schedule(function() callback { items = {}, is_incomplete_forward = false, is_incomplete_backward = false } end)
      return
    end
    local parsed = parse_versions(res.stdout)
    if parsed then cache[pkg] = parsed end
    vim.schedule(
      function()
        callback {
          items = parsed and build_items(parsed, typed, row, start_col, end_col) or {},
          is_incomplete_forward = true,
          is_incomplete_backward = true,
        }
      end
    )
  end)

  return function()
    pcall(function() job:kill(9) end)
  end
end

return source

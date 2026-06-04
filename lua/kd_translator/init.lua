---@alias KdTranslator.WordJsonFormatter fun(data: KdTranslator.WordJsonData, lines: string[], ranges: KdTranslator.HLRange[], row: integer): integer

---@alias KdTranslator.ExampleLineFormatter fun(data: KdTranslator.ExampleLineData, lines: string[], ranges: KdTranslator.HLRange[], row: integer): integer

---@alias KdTranslator.OperatorMode "char"|"line"|"block"|"visual"

---@class KdTranslator.Hooks
---@field pre_process? fun(text: string): string
---@field build_cmd? fun(text: string): string[]
---@field format_word_phonetic? KdTranslator.WordJsonFormatter
---@field format_definitions? KdTranslator.WordJsonFormatter
---@field format_level? KdTranslator.WordJsonFormatter
---@field format_example_line? KdTranslator.ExampleLineFormatter
---@field format_co_li? KdTranslator.WordJsonFormatter
---@field format_au_bi_or? KdTranslator.WordJsonFormatter
---@field format_examples? KdTranslator.WordJsonFormatter

---@class KdTranslator.Opts
---@field cmd? string `kd` or command fullpath
---@field preview_opts? vim.lsp.util.open_floating_preview.Opts
---@field hook? KdTranslator.Hooks

---@class KdTranslator
local M = {}

local H = {}

H.did_setup = false
H.ns = vim.api.nvim_create_namespace('KdTranslator')
H.augroup = vim.api.nvim_create_augroup('KdTranslator', { clear = true })

---@type KdTranslator.Opts
H.config = {
  cmd = 'kd',
  preview_opts = {
    border = vim.o.winborder or 'rounded',
    title = ' Translator ',
    focus_id = 'KdTranslatorWindow',
    max_width = 80,
    max_height = 50,
  },
  hook = {
    pre_process = function(text) return text end,
    build_cmd = function(text)
      if text:find('[\xE4-\xE9][\x80-\xBF][\x80-\xBF]') or text:find('%s') then return { H.config.cmd, '-t', text } end
      return { H.config.cmd, '--json', text }
    end,
    format_word_phonetic = function(...) return H.format_word_phonetic(...) end,
    format_definitions = function(...) return H.format_definitions(...) end,
    format_level = function(...) return H.format_level(...) end,
    format_example_line = function(...) return H.format_example_line(...) end,
    format_co_li = function(...) return H.format_co_li(...) end,
    format_au_bi_or = function(...) return H.format_au_bi_or(...) end,
    format_examples = function(...) return H.format_examples(...) end,
  },
}

---@class KdTranslator.OperatorRegion
---@field mark_from string
---@field mark_to string
---@field submode string

H.submode_keys = {
  char = 'v',
  line = 'V',
  block = vim.api.nvim_replace_termcodes('<C-v>', true, true, true),
}

---@param mode string
---@return KdTranslator.OperatorRegion?
function H.operator_region(mode)
  local submode
  if mode == 'visual' then
    if vim.fn.mode():match('[vV\22]') then vim.cmd('normal! \27') end
    submode = vim.fn.visualmode()
  else
    submode = H.submode_keys[mode]
  end
  if not submode then return nil end

  local mark_from = mode == 'visual' and '<' or '['
  local mark_to = mode == 'visual' and '>' or ']'

  local pa, pb = vim.api.nvim_buf_get_mark(0, mark_from), vim.api.nvim_buf_get_mark(0, mark_to)
  if pb[1] < pa[1] or (pb[1] == pa[1] and pb[2] < pa[2]) then return nil end

  return { mark_from = mark_from, mark_to = mark_to, submode = submode }
end

---@param mark_from string
---@param mark_to string
---@param opts? {submode?: string, register?: string, silent?: boolean}
---@return string|nil
function H.region_text(mark_from, mark_to, opts)
  opts = opts or {}
  local submode = opts.submode or 'v'
  local reg = opts.register or 'x'
  local silent = opts.silent ~= false

  local reginfo = vim.fn.getreginfo(reg)
  local default_reg = vim.fn.getreginfo('"')
  local save_cursor = vim.api.nvim_win_get_cursor(0)

  local cache_ei = vim.o.eventignore
  vim.o.eventignore = 'TextYankPost'
  local cache_sel = vim.o.selection
  vim.o.selection = 'inclusive'
  local cache_ve = vim.o.virtualedit
  vim.o.virtualedit = 'onemore'

  local prefix = silent and 'silent ' or ''
  vim.cmd(prefix .. 'normal! `' .. mark_from .. '"' .. reg .. 'y' .. submode .. '`' .. mark_to)

  vim.o.virtualedit = cache_ve
  vim.o.selection = cache_sel
  vim.o.eventignore = cache_ei

  vim.api.nvim_win_set_cursor(0, save_cursor)
  vim.fn.setreg('"', default_reg)

  local lines = vim.fn.getreg(reg, 1, true)
  vim.fn.setreg(reg, reginfo)

  return #lines > 0 and table.concat(lines, '\n') or nil
end

---@param mode KdTranslator.OperatorMode
---@return string|nil
function H.operator_text(mode)
  local region = H.operator_region(mode)
  if not region then return nil end
  return H.region_text(region.mark_from, region.mark_to, { submode = region.submode })
end

---@param stdout string
---@return string[]
function H.filter_stdout(stdout)
  return vim
    .iter(vim.gsplit(stdout, '\n'))
    :filter(
      function(line) return not line:find('未找到守护进程') and not line:find('成功启动守护进程') end
    )
    :totable()
end

---@param args string[]
---@param callback fun(err: string|nil, lines: string[])
function H.run_kd(args, callback)
  vim.system(args, { text = true, env = { NO_COLOR = 1 } }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local err = result.stderr and result.stderr:match('^%s*(.-)%s*$') or 'unknown'
        callback(err, {})
        return
      end
      callback(nil, H.filter_stdout(result.stdout))
    end)
  end)
end

---@class KdTranslator.HLRange
---@field group string
---@field row integer
---@field col_s integer
---@field col_e integer

---@class KdTranslator.WordJsonData
---@field k string
---@field pron? table<string, string>
---@field para? string[]
---@field eg? { au?: string[][], bi?: string[][], or?: string[][] }
---@field co? { star?: integer, rank?: string, pat?: string, li?: { a?: string, maj?: string, eg?: string[][] }[] }

---@class KdTranslator.ExampleLineData
---@field en string
---@field cn? string
---@field source? string

---@param data KdTranslator.WordJsonData
---@param lines string[]
---@param ranges KdTranslator.HLRange[]
---@param row integer
---@return integer
function H.format_word_phonetic(data, lines, ranges, row)
  if not data.k or #data.k == 0 then return row end

  local word_line = data.k
  if data.pron and next(data.pron) then
    local parts = {}
    for _, accent in ipairs({ '美', '英' }) do
      if data.pron[accent] then
        local p = data.pron[accent]:match('^%[(.-)%]$') or data.pron[accent]
        table.insert(parts, accent .. ' ' .. p)
      end
    end
    if #parts > 0 then word_line = word_line .. '    [' .. table.concat(parts, ' / ') .. ']' end
  end

  table.insert(lines, word_line)
  table.insert(ranges, { group = 'KdTranslatorWord', row = row, col_s = 0, col_e = #data.k })
  if #word_line > #data.k then
    local phon_start = #data.k + 4
    table.insert(ranges, {
      group = 'KdTranslatorPhonetic',
      row = row,
      col_s = phon_start,
      col_e = #word_line,
    })
  end

  return row + 1
end

---@param data KdTranslator.WordJsonData
---@param lines string[]
---@param ranges KdTranslator.HLRange[]
---@param row integer
---@return integer
function H.format_definitions(data, lines, ranges, row)
  if not data.para or #data.para == 0 then return row end

  for _, para in ipairs(data.para) do
    table.insert(lines, para)

    if not para:match('^[A-Za-z]+ ') then
      local space_pos = para:find(' ')
      if space_pos then table.insert(ranges, { group = 'KdTranslatorPos', row = row, col_s = 0, col_e = space_pos }) end
    end

    row = row + 1
  end

  return row
end

---@param data KdTranslator.WordJsonData
---@param lines string[]
---@param ranges KdTranslator.HLRange[]
---@param row integer
---@return integer
function H.format_level(data, lines, ranges, row)
  if not data.co then return row end

  local tokens = {}
  if data.co.star and data.co.star > 0 then table.insert(tokens, string.rep('★', data.co.star)) end
  if data.co.rank and #data.co.rank > 0 then table.insert(tokens, data.co.rank) end
  if data.co.pat and #data.co.pat > 0 then table.insert(tokens, data.co.pat) end
  if #tokens == 0 then return row end

  local level_line = table.concat(tokens, ' ')
  table.insert(lines, level_line)

  local col = 0
  for _, token in ipairs(tokens) do
    table.insert(ranges, {
      group = 'KdTranslatorLevel',
      row = row,
      col_s = col,
      col_e = col + #token,
    })
    col = col + #token + 1
  end

  return row + 1
end

local PREFIX = '   ≫   '

---@param data KdTranslator.ExampleLineData
---@param lines string[]
---@param ranges KdTranslator.HLRange[]
---@param row integer
---@return integer
function H.format_example_line(data, lines, ranges, row)
  local en = data.en
  local cn = data.cn
  local source = data.source
  local pair_line = PREFIX .. en
  local cn_start = 0
  if cn and #cn > 0 then
    pair_line = pair_line .. '  ' .. cn
    cn_start = #PREFIX + #en + 2
  end
  if source and #source > 0 then pair_line = pair_line .. '  (' .. source .. ')' end

  table.insert(lines, pair_line)
  table.insert(ranges, { group = 'KdTranslatorExampleCn', row = row, col_s = 0, col_e = #PREFIX })
  table.insert(ranges, {
    group = 'KdTranslatorExampleEn',
    row = row,
    col_s = #PREFIX,
    col_e = #PREFIX + #en,
  })
  if cn and #cn > 0 then
    table.insert(ranges, {
      group = 'KdTranslatorExampleCn',
      row = row,
      col_s = cn_start,
      col_e = cn_start + #cn,
    })
  end

  return row + 1
end

---@param data KdTranslator.WordJsonData
---@param lines string[]
---@param ranges KdTranslator.HLRange[]
---@param row integer
---@return integer
function H.format_co_li(data, lines, ranges, row)
  if not data.co or not data.co.li or #data.co.li == 0 then return row end

  for idx, item in ipairs(data.co.li) do
    item.a = item.a ~= vim.NIL and item.a or nil
    item.maj = item.maj ~= vim.NIL and item.maj or nil
    item.eg = item.eg ~= vim.NIL and item.eg or nil

    local num_str = idx .. '.'
    local label = item.a or ''
    local num_label = num_str .. ' ' .. label
    local eg_line = num_label
    if item.maj and #item.maj > 0 then eg_line = eg_line .. ' ' .. item.maj end
    table.insert(lines, eg_line)

    table.insert(ranges, {
      group = 'KdTranslatorExampleNum',
      row = row,
      col_s = 0,
      col_e = #num_str,
    })
    if #label > 0 then
      table.insert(ranges, {
        group = 'KdTranslatorExampleLabel',
        row = row,
        col_s = #num_str + 1,
        col_e = #num_str + 1 + #label,
      })
    end
    row = row + 1

    if item.eg then
      for _, eg_pair in ipairs(item.eg) do
        row = H.config.hook.format_example_line({ en = eg_pair[1] or '', cn = eg_pair[2] or '' }, lines, ranges, row)
      end
    end
  end

  return row
end

---@param data KdTranslator.WordJsonData
---@param lines string[]
---@param ranges KdTranslator.HLRange[]
---@param row integer
---@return integer
function H.format_au_bi_or(data, lines, ranges, row)
  if not data.eg or not next(data.eg) then return row end

  for _, group_key in ipairs({ 'au', 'bi', 'or' }) do
    local group = data.eg[group_key]
    if group and #group > 0 then
      for _, entry in ipairs(group) do
        local d = { en = entry[1] or '' }
        if group_key == 'au' then
          d.source = entry[2] or ''
        else
          d.cn = entry[2] or ''
          d.source = entry[3] or ''
        end
        row = H.config.hook.format_example_line(d, lines, ranges, row)
      end
    end
  end

  return row
end

---@param data KdTranslator.WordJsonData
---@param lines string[]
---@param ranges KdTranslator.HLRange[]
---@param row integer
---@return integer
function H.format_examples(data, lines, ranges, row)
  local has_co_li = data.co and data.co.li and #data.co.li > 0
  local has_eg = data.eg and next(data.eg)
  if not has_co_li and not has_eg then return row end

  table.insert(lines, '')
  row = row + 1

  local h = H.config.hook

  if has_co_li then
    ---@diagnostic disable-next-line: need-check-nil
    row = h.format_co_li(data, lines, ranges, row)
  elseif has_eg then
    ---@diagnostic disable-next-line: need-check-nil
    row = h.format_au_bi_or(data, lines, ranges, row)
  end

  return row
end

---@param data table parsed from `kd --json`
---@return string[], KdTranslator.HLRange[]
function M.format_word_json(data)
  local function val(v) return v ~= vim.NIL and v or nil end

  data.k = val(data.k)
  data.pron = val(data.pron)
  data.para = val(data.para)
  data.eg = val(data.eg)
  if data.co then
    data.co.rank = val(data.co.rank)
    data.co.pat = val(data.co.pat)
    data.co.li = val(data.co.li)
  else
    data.co = val(data.co)
  end

  local lines = {}
  local ranges = {} ---@type KdTranslator.HLRange[]
  local row = 0

  local h = H.config.hook

  ---@diagnostic disable: need-check-nil
  row = h.format_word_phonetic(data, lines, ranges, row)
  row = h.format_definitions(data, lines, ranges, row)
  row = h.format_level(data, lines, ranges, row)
  row = h.format_examples(data, lines, ranges, row)
  ---@diagnostic enable: need-check-nil

  return lines, ranges
end

---@param lines string[]
---@param ranges KdTranslator.HLRange[]
function H.show_float(lines, ranges)
  if not lines or #lines == 0 then return end
  local bufnr, _winid = vim.lsp.util.open_floating_preview(lines, 'plaintext', H.config.preview_opts)
  for _, r in ipairs(ranges) do
    vim.hl.range(bufnr, H.ns, r.group, { r.row, r.col_s }, { r.row, r.col_e })
  end
end

---@param text string
---@param callback fun(err: string|nil, lines?: string[], ranges?: KdTranslator.HLRange[])
function M.translate_word_and_format(text, callback)
  H.run_kd({ H.config.cmd, '--json', text }, function(err, raw_lines)
    if err then
      callback(err, {}, {})
      return
    end
    if not raw_lines or #raw_lines == 0 then
      callback('empty response', {}, {})
      return
    end
    local ok, data = pcall(vim.json.decode, table.concat(raw_lines, '\n'))
    if not ok or not data then
      callback('invalid json response', {}, {})
      return
    end
    if not data.k or #data.k == 0 then
      callback('no result', {}, {})
      return
    end
    callback(nil, M.format_word_json(data))
  end)
end

---@return integer
function M.get_ns() return H.ns end

---@param buf integer
---@param ranges KdTranslator.HLRange[]
function M.apply_highlights(buf, ranges)
  for _, r in ipairs(ranges) do
    vim.hl.range(buf, H.ns, r.group, { r.row, r.col_s }, { r.row, r.col_e })
  end
end

---@param text string
function M.translate_preview(text)
  local trimmed = text:match('^%s*(.-)%s*$') or text
  local cleaned = H.config.hook.pre_process(trimmed)
  if #cleaned == 0 then return end

  local args = H.config.hook.build_cmd(cleaned)

  local is_paragraph = false
  for i = 1, #args - 1 do
    if args[i] == '-t' or args[i] == '--text' then
      is_paragraph = true
      break
    end
  end

  if is_paragraph then
    H.run_kd(args, function(err, lines)
      if err or not lines or #lines == 0 then
        vim.notify('kd: ' .. (err or 'no result'), vim.log.levels.INFO, { title = 'KdTranslator' })
        return
      end
      local ranges = {} ---@type KdTranslator.HLRange[]
      if lines[1] then
        table.insert(ranges, {
          group = 'KdTranslatorTextQuery',
          row = 0,
          col_s = 0,
          col_e = #lines[1],
        })
      end
      if lines[2] then
        table.insert(ranges, {
          group = 'KdTranslatorTextResult',
          row = 1,
          col_s = 0,
          col_e = #lines[2],
        })
      end
      H.show_float(lines, ranges)
    end)
  else
    H.run_kd(args, function(err, raw_lines)
      if err then
        vim.notify('kd: ' .. err, vim.log.levels.INFO, { title = 'KdTranslator' })
        return
      end
      if not raw_lines or #raw_lines == 0 then
        vim.notify('kd: no result', vim.log.levels.INFO, { title = 'KdTranslator' })
        return
      end
      local ok, data = pcall(vim.json.decode, table.concat(raw_lines, '\n'))
      if not ok or not data or not data.k or #data.k == 0 then
        vim.notify('kd: no result', vim.log.levels.INFO, { title = 'KdTranslator' })
        return
      end
      H.show_float(M.format_word_json(data))
    end)
  end
end

---@param mode KdTranslator.OperatorMode
function M.operator(mode)
  local text = H.operator_text(mode)
  if text then M.translate_preview(text) end
end

function H.create_default_hl()
  vim.api.nvim_set_hl(0, 'KdTranslatorWord', { link = 'Title' })
  vim.api.nvim_set_hl(0, 'KdTranslatorPhonetic', { link = '@comment' })
  vim.api.nvim_set_hl(0, 'KdTranslatorPos', { link = 'Type' })
  vim.api.nvim_set_hl(0, 'KdTranslatorLevel', { link = 'Keyword' })
  vim.api.nvim_set_hl(0, 'KdTranslatorExampleNum', { link = 'Constant' })
  vim.api.nvim_set_hl(0, 'KdTranslatorExampleLabel', { link = 'DiagnosticHint' })
  vim.api.nvim_set_hl(0, 'KdTranslatorExampleEn', { link = '@comment' })
  vim.api.nvim_set_hl(0, 'KdTranslatorExampleCn', { link = '@comment' })
  vim.api.nvim_set_hl(0, 'KdTranslatorTextQuery', { link = 'Identifier' })
  vim.api.nvim_set_hl(0, 'KdTranslatorTextResult', { link = 'String' })
end

function H.create_autocmd()
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = H.augroup,
    desc = 'KdTranslator.Autocmds.OnColorScheme',
    callback = H.create_default_hl,
  })
end

function H.create_keymaps()
  _G.__kd_translator_operator = M.operator

  vim.api.nvim_create_user_command('KdTranslator', function(info)
    local text
    if info.range ~= 0 then text = H.region_text('<', '>', { submode = vim.fn.visualmode() }) end
    text = text or vim.fn.expand('<cword>')
    if text and #text > 0 then M.translate_preview(text) end
  end, { range = true, desc = 'Translate word or visual selection' })

  vim.keymap.set('n', '<Plug>(kd-translator-operator)', function()
    vim.o.operatorfunc = 'v:lua.__kd_translator_operator'
    return 'g@'
  end, { expr = true, desc = 'Kd Translate Operator' })

  vim.keymap.set(
    'x',
    '<Plug>(kd-translator-visual)',
    function() M.operator('visual') end,
    { desc = 'Kd Translate selection' }
  )
end

---@param opts? KdTranslator.Opts
function M.setup(opts)
  if H.did_setup then return end
  H.did_setup = true

  H.config = vim.tbl_deep_extend('force', H.config, opts or {})

  if vim.fn.executable(H.config.cmd) == 0 then
    vim.notify('kd: executable not found', vim.log.levels.WARN, { title = 'KdTranslator' })
    return
  end

  H.create_default_hl()

  H.create_autocmd()

  H.create_keymaps()
end

return M

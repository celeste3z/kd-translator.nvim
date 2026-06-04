--- *kd-translator* KdTranslator - plugin for kd CLI dictionary
---
--- MIT License Copyright (c) 2026 celeste3z
---
--- ------------------------------------------------------------------------------
---                                                                   *KdTranslator*
---
--- # Dependencies ~
---
--- - https://github.com/Karmenzind/kd
--- - Optional: `vim-repeat` (https://github.com/tpope/vim-repeat) for dot-repeat support
---
--- # Features ~
--- - Translate words via `kd --json` with rich formatting (phonetic, definitions, level, examples)
--- - Translate paragraphs via `kd -t`
--- - Floating preview window
--- - Operator-pending mode for quick translation
--- - Customizable formatting via hooks
--- - Dot-repeat support via `vim-repeat` (optional)
--- - Dictionary complete integration
---
--- # Setup ~
---
--- This module needs a setup with `require('kd-translator').setup({})`.
--- See |kd-translator-config| for structure and default values.
---
--- # Keymaps example ~
---                                       *kd-translator-keymaps-example*
---
--- The plugin provides two `<Plug>` mappings as building blocks:
---
--- - `<Plug>(kd-translator-operator)` `n` - Operator-pending mode for motions
--- - `<Plug>(kd-translator-visual)` `x` - Translate visual selection
---
--- Basic keymaps:
---
--- >lua
---   -- gt + motion: translate text object (iw, ip, iW, etc.)
---   vim.keymap.set('n', 'gt', '<Plug>(kd-translator-operator)')
---   -- gt in visual mode: translate selection
---   vim.keymap.set('x', 'gt', '<Plug>(kd-translator-visual)')
--- <
---
--- Press `gt` then a motion (like `iw`) to translate that text object.
--- Press the same keybinding again (e.g. `gtiw` or `<Leader>tw`) to return focus to the preview window.
---
--- For quicker access, bind the operator + motion together:
---
--- >lua
---   -- Quick translate word under cursor:
---   vim.keymap.set('n', '<Leader>tw', '<Plug>(kd-translator-operator)iw')
---   -- Quick translate paragraph:
---   vim.keymap.set('n', '<Leader>tp', '<Plug>(kd-translator-operator)ip')
---   -- Translate visual selection:
---   vim.keymap.set('x', '<Leader>t', '<Plug>(kd-translator-visual)')
--- <
---
--- # Notes ~
---
--- If `vim-repeat` is installed, pressing `.` after translation re-enters the
--- preview window. It also enables dot-repeat: translate "hello" with `gtiw`,
--- then move to "world" and press `.` to quickly translate it without repeating
--- the full keybinding.
---
--- # Command ~
---
--- `:KdTranslator` {range}
---
--- If given a range (visual selection), translates the selected text.
--- Otherwise translates the word under cursor (`<cword>`).
---
--- Created automatically by |KdTranslator.setup()|.
---
--- Usage:
---
--- >lua
---   " Translate word under cursor:
---   :KdTranslator
---
---   " Translate visual selection:
---   :'<,'>KdTranslator
--- <
---
--- # Dictionary complete integration ~
---
--- See |kd-translator-blink-cmp-dictionary| for a usage example with `blink-cmp-dictionary`.
---
--- # Highlight groups ~
---                                    *kd-translator-highlight-groups*
---
--- - `KdTranslatorWord`           - word text            -> `Title`
--- - `KdTranslatorPhonetic`       - phonetic notation    -> `@comment`
--- - `KdTranslatorPos`            - part of speech label -> `Type`
--- - `KdTranslatorLevel`          - level stars and rank -> `Keyword`
--- - `KdTranslatorExampleNum`     - example number       -> `Constant`
--- - `KdTranslatorExampleLabel`   - collocation label    -> `DiagnosticHint`
--- - `KdTranslatorExampleEn`      - example English      -> `@comment`
--- - `KdTranslatorExampleCn`      - example Chinese      -> `@comment`
--- - `KdTranslatorTextQuery`      - paragraph query text -> `Identifier`
--- - `KdTranslatorTextResult`     - paragraph result     -> `String`

---@alias KdTranslator.WordJsonFormatter fun(data: KdTranslator.WordJsonData, lines: string[], ranges: KdTranslator.HLRange[], row: integer): integer

---@alias KdTranslator.ExampleLineFormatter fun(data: KdTranslator.ExampleLineData, lines: string[], ranges: KdTranslator.HLRange[], row: integer): integer

---@alias KdTranslator.OperatorMode "char"|"line"|"block"|"visual"

---@class KdTranslator.Hooks
--- Table of optional hook functions to customize formatting behavior
---@field pre_process? fun(text: string): string
---@field build_cmd? fun(text: string): string[]
---@field format_word_phonetic? KdTranslator.WordJsonFormatter
---@field format_definitions? KdTranslator.WordJsonFormatter
---@field format_level? KdTranslator.WordJsonFormatter
---@field format_example_line? KdTranslator.ExampleLineFormatter
---@field format_co_li? KdTranslator.WordJsonFormatter
---@field format_au_bi_or? KdTranslator.WordJsonFormatter
---@field format_examples? KdTranslator.WordJsonFormatter
---@text
---
--- # Hooks ~
---
--- All hook fields are optional. By default each delegates to the internal formatter
--- (see |KdTranslator.format_word_json()|).
---
--- Example of custom `pre_process` (called before text is sent to kd):
---
--- >lua
---   require('kd-translator').setup({
---     hook = {
---       pre_process = function(text)
---         -- Strip markdown link syntax: [text](url) -> text
---         return text:gsub('%[([^%[%]]+)%]%(%S+%)', '%1')
---       end,
---     },
---   })
--- <
---
--- Example of custom `format_level` (called to render star/rank line):
---
--- >lua
---   require('kd-translator').setup({
---     hook = {
---       format_level = function(data, lines, ranges, row)
---         -- Only show stars, ignore rank and pattern
---         if data.co and data.co.star then
---           table.insert(lines, string.rep('★', data.co.star))
---           row = row + 1
---         end
---         return row
---       end,
---     },
---   })
--- <

---@class KdTranslator.Opts
--- Module configuration table
---@field cmd? string `kd` or command fullpath
---@field preview_opts? vim.lsp.util.open_floating_preview.Opts
---@field hook? KdTranslator.Hooks

---@private
---@class KdTranslator
local KdTranslator = {}

local H = {}

H.did_setup = false
H.ns = vim.api.nvim_create_namespace('KdTranslator')
H.augroup = vim.api.nvim_create_augroup('KdTranslator', { clear = true })

--- KdTranslator.config                                             *kd-translator-config*
---
--- `KdTranslator.Opts` is a table with the following fields:
---
--- - {cmd} `(string)` Path to `kd` executable. Default: `'kd'`.
--- - {preview_opts} `(vim.lsp.util.open_floating_preview.Opts)`
--- - {hook} `(KdTranslator.Hooks|nil)` Customization hooks.
---
--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)

--@type KdTranslator.Opts
H.config = {
  -- Path to `kd` executable
  cmd = 'kd',

  -- Options for floating preview window
  preview_opts = {
    border = vim.o.winborder or 'rounded',
    title = ' Translator ',
    focus_id = 'KdTranslatorWindow',
    max_width = 80,
    max_height = 50,
  },

  -- Customization hooks (all optional)
  hook = {
    -- Transform text before passing to kd
    -- Default: returns text unchanged
    pre_process = function(text) return text end,

    -- Build command arguments. Return {"kd", flag, text}
    -- Default: if text contains CJK or whitespace, uses "-t" (paragraph);
    -- otherwise uses "--json" (word lookup)
    build_cmd = function(text)
      if text:find('[\xE4-\xE9][\x80-\xBF][\x80-\xBF]') or text:find('%s') then return { H.config.cmd, '-t', text } end
      return { H.config.cmd, '--json', text }
    end,

    -- Format word + phonetic line (row 0)
    format_word_phonetic = function(...) return H.format_word_phonetic(...) end,

    -- Format definitions: each line = "pos. definition"
    format_definitions = function(...) return H.format_definitions(...) end,

    -- Format level line: stars + rank + pattern
    format_level = function(...) return H.format_level(...) end,

    -- Format single example pair (en + cn)
    format_example_line = function(...) return H.format_example_line(...) end,

    -- Format collocations with numbered items
    format_co_li = function(...) return H.format_co_li(...) end,

    -- Format examples grouped by type (au, bi, or)
    format_au_bi_or = function(...) return H.format_au_bi_or(...) end,

    -- Top-level examples orchestrator (calls co_li or au_bi_or)
    format_examples = function(...) return H.format_examples(...) end,
  },
}

---@class KdTranslator.OperatorRegion
--- Region marks and submode for operator text extraction
---@field mark_from string
---@field mark_to string
---@field submode string

H.submode_keys = {
  char = 'v',
  line = 'V',
  block = vim.api.nvim_replace_termcodes('<C-v>', true, true, true),
}

---@private
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

---@private
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

---@private
---@param mode KdTranslator.OperatorMode
---@return string|nil
function H.operator_text(mode)
  local region = H.operator_region(mode)
  if not region then return nil end
  return H.region_text(region.mark_from, region.mark_to, { submode = region.submode })
end

---@private
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

---@private
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
--- Highlight range (row, column start/end, group name)
---@field group string
---@field row integer
---@field col_s integer
---@field col_e integer

---@class KdTranslator.WordJsonData
--- Parsed JSON data from `kd --json` word lookup
---@field k string
---@field pron? table<string, string>
---@field para? string[]
---@field eg? { au?: string[][], bi?: string[][], or?: string[][] }
---@field co? { star?: integer, rank?: string, pat?: string, li?: { a?: string, maj?: string, eg?: string[][] }[] }

---@class KdTranslator.ExampleLineData
--- Single example line data (en, cn, optional source)
---@field en string
---@field cn? string
---@field source? string

---@private
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

---@private
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

---@private
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

---@private
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

---@private
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

---@private
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

---@private
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

--- Format word JSON data into display lines and highlight ranges
---
--- Calls hook formatters in sequence: word/phonetic, definitions, level, examples.
---
---@param data table Parsed JSON from `kd --json`
---@return string[]
---@return KdTranslator.HLRange[]
function KdTranslator.format_word_json(data)
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

--- Process raw stdout from `kd --json` into formatted lines and ranges.
---
--- Pipeline: filter_stdout -> json.decode -> format_word_json
---
---@param raw_output string Raw stdout from `kd --json`
---@return string[] lines
---@return KdTranslator.HLRange[] ranges
---
---                                        *kd-translator-blink-cmp-dictionary*
--- Usage example with `blink-cmp-dictionary` for `blink.cmp`:
---
--- >lua
---   dictionary = {
---     module = "blink-cmp-dictionary",
---     name = "Dict",
---     min_keyword_length = 3,
---     opts = {
---       dictionary_files = { "path/to/your/dictionary.txt" },
---       get_documentation = function(item)
---         return {
---           get_command = function() return "kd" end,
---           get_command_args = function() return { "--json", item } end,
---           resolve_documentation = function(output)
---             local kd = require("kd-translator")
---             local lines, ranges = kd.format_raw_word_output(output)
---             if #lines == 0 then return nil end
---             return {
---               draw = function(opts)
---                 kd.render(opts.window:get_buf(), lines, ranges)
---               end,
---             }
---           end,
---         }
---       end,
---     },
---   },
--- <
function KdTranslator.format_raw_word_output(raw_output)
  local filtered = H.filter_stdout(raw_output)
  if #filtered == 0 then return {}, {} end
  local ok, data = pcall(vim.json.decode, table.concat(filtered, '\n'))
  if not ok or not data or not data.k or #data.k == 0 then return {}, {} end
  return KdTranslator.format_word_json(data)
end

---@private
---@param lines string[]
---@param ranges KdTranslator.HLRange[]
function H.show_float(lines, ranges)
  if not lines or #lines == 0 then return end
  local bufnr, _winid = vim.lsp.util.open_floating_preview(lines, 'plaintext', H.config.preview_opts)
  for _, r in ipairs(ranges) do
    vim.hl.range(bufnr, H.ns, r.group, { r.row, r.col_s }, { r.row, r.col_e })
  end
end

--- Run `kd --json` and format the result via |KdTranslator.format_word_json()|
---
---@param text string Word to look up
---@param callback fun(err: string|nil, lines?: string[], ranges?: KdTranslator.HLRange[])
function KdTranslator.translate_word_and_format(text, callback)
  H.run_kd({ H.config.cmd, '--json', text }, function(err, raw_lines)
    if err then
      callback(err, {}, {})
      return
    end
    local lines, ranges = KdTranslator.format_raw_word_output(table.concat(raw_lines or {}, '\n'))
    if #lines == 0 then
      callback('no result', {}, {})
      return
    end
    callback(nil, lines, ranges)
  end)
end

---@return integer Highlight namespace ID. Useful for external highlight management.
function KdTranslator.get_ns() return H.ns end

--- Render formatted translation output in a buffer.
---
--- Clears the namespace, sets lines, and applies highlight ranges.
---
---@param buf integer
---@param lines string[]
---@param ranges KdTranslator.HLRange[]
function KdTranslator.render(buf, lines, ranges)
  vim.api.nvim_buf_clear_namespace(buf, H.ns, 0, -1)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for _, r in ipairs(ranges) do
    vim.hl.range(buf, H.ns, r.group, { r.row, r.col_s }, { r.row, r.col_e })
  end
end

--- Translate text and show result in floating preview window
---
--- Uses `kd --json` for single words and `kd -t` for paragraphs or Chinese text.
---
---@param text string Text to translate
---@usage >lua
---   require('kd-translator').translate_preview('hello')
--- <
function KdTranslator.translate_preview(text)
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
      H.show_float(KdTranslator.format_word_json(data))
    end)
  end
end

--- Operator function for operator-pending mode
---
--- Called by `<Plug>(kd-translator-operator)`. Extracts text from the operator
--- region and translates it via |KdTranslator.translate_preview()|.
---
---@param mode KdTranslator.OperatorMode
function KdTranslator.operator(mode)
  local text = H.operator_text(mode)
  if text then KdTranslator.translate_preview(text) end
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
  _G.__kd_translator_operator = KdTranslator.operator

  vim.api.nvim_create_user_command('KdTranslator', function(info)
    local text
    if info.range ~= 0 then text = H.region_text('<', '>', { submode = vim.fn.visualmode() }) end
    text = text or vim.fn.expand('<cword>')
    if text and #text > 0 then KdTranslator.translate_preview(text) end
  end, { range = true, desc = 'Translate word or visual selection' })

  vim.keymap.set('n', '<Plug>(kd-translator-operator)', function()
    vim.o.operatorfunc = 'v:lua.__kd_translator_operator'
    return 'g@'
  end, { expr = true, desc = 'Kd Translate Operator' })

  vim.keymap.set(
    'x',
    '<Plug>(kd-translator-visual)',
    function() KdTranslator.operator('visual') end,
    { desc = 'Kd Translate selection' }
  )
end

--- Module setup
---
--- Must be called before using the plugin. Creates highlight groups,
--- autocmds, and |kd-translator-keymaps-example|.
---
---@param opts? KdTranslator.Opts
---@usage >lua
---   require('kd-translator').setup()
---   require('kd-translator').setup({ cmd = '/path/to/kd' })
--- <
function KdTranslator.setup(opts)
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

return KdTranslator

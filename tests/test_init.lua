local helpers = dofile('tests/helpers.lua')
local child = helpers.new_child_neovim()
local eq = MiniTest.expect.equality
local new_set = MiniTest.new_set

local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.load_module()
    end,
    post_once = child.stop,
  },
})

-- ====================================================================
-- format_word_json
-- ====================================================================
T['format_word_json'] = new_set()

T['format_word_json']['formats basic word data'] = function()
  local data = {
    k = 'hello',
    pron = { ['美'] = '/həˈloʊ/', ['英'] = '/həˈləʊ/' },
    para = { 'int. 你好；喂', 'n. 问候语' },
    co = { star = 4, rank = '500', pat = '[C]' },
    eg = {
      bi = {
        { 'Hello, how are you?', '你好，你怎么样？' },
        { 'She said hello to me.', '她向我打了招呼。' },
      },
    },
  }
  local lines = child.lua(
    [[
    local kd = require('kd-translator')
    local l, _ = kd.format_word_json(...)
    return l
  ]],
    { data }
  )

  -- Word + phonetic line
  eq(true, (#lines >= 7), 'should have enough lines')

  -- Check word line (line 1)
  eq(true, lines[1]:find('hello') ~= nil, 'line 0 should contain word')
  eq(true, lines[1]:find('美') ~= nil, 'line 0 should contain phonetic label')

  -- Definitions (lines 2-3)
  eq(true, lines[2]:find('int%.') ~= nil, 'line 1 should contain POS')
  eq(true, lines[2]:find('你好') ~= nil, 'line 1 should contain Chinese def')
  eq(true, lines[3]:find('n%.') ~= nil, 'line 2 should contain POS')

  -- Level (line 4)
  eq(true, lines[4]:find('★★★★') ~= nil, 'line 3 should contain stars')
  eq(true, lines[4]:find('500') ~= nil, 'line 3 should contain rank')

  -- Examples (lines 6-7)
  eq(true, lines[6]:find('Hello') ~= nil, 'line 5 should contain example EN')
  eq(true, lines[6]:find('你好') ~= nil, 'line 5 should contain example CN')
  eq(true, lines[7]:find('She said') ~= nil, 'line 6 should contain 2nd example')
end

T['format_word_json']['handles minimal data'] = function()
  local data = { k = 'test', para = { 'n. 测试' } }
  local lines = child.lua(
    [[
    local kd = require('kd-translator')
    local l, _ = kd.format_word_json(...)
    return l
  ]],
    { data }
  )

  eq(#lines, 2, 'should have word line and definition line')
  eq(lines[1], 'test', 'word line should be the word')
  eq(lines[2], 'n. 测试', 'definition line should be correct')
end

T['format_word_json']['handles missing optional fields'] = function()
  local data = { k = 'minimal' }
  local lines = child.lua(
    [[
    local kd = require('kd-translator')
    local l, _ = kd.format_word_json(...)
    return l
  ]],
    { data }
  )

  eq(true, (#lines >= 1), 'should have at least word line')
  eq(lines[1], 'minimal', 'word line should be the word')
end

-- ====================================================================
-- Operator motions
-- ====================================================================
T['operator'] = new_set()

T['operator']['gtiw on English word'] = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.load_module()
      child.set_lines({ 'say hello to the world' })
      child.set_cursor(1, 4)
    end,
  },
})
T['operator']['gtiw on English word']['opens float with word result'] = function()
  child.lua('vim.cmd("normal gtiw")')
  local content = child.get_float_content()
  eq(true, content ~= nil and #content > 0, 'floating window should appear')
  local text = table.concat(content, '\n')
  eq(true, text:find('hello') ~= nil, 'should contain the word')
  eq(true, text:find('həˈloʊ') ~= nil, 'should contain phonetic')
  eq(true, text:find('int%.') ~= nil or text:find('n%.') ~= nil, 'should contain POS')
  eq(true, text:find('你好') ~= nil, 'should contain Chinese definition')
  eq(true, text:find('Hello, how') ~= nil, 'should contain example sentence')
end

T['operator']['gtip on Chinese paragraph'] = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.load_module()
      child.set_lines({
        'first unrelated paragraph',
        '',
        '有时候，生活中总有些东西在等待着我们去发现。',
        '它可能是一个新的想法，也可能是一段新的经历。',
        '无论是什么，都值得我们去追寻。',
        '',
        'another unrelated paragraph',
      })
      child.set_cursor(3, 1)
    end,
  },
})
T['operator']['gtip on Chinese paragraph']['opens float with paragraph translation'] = function()
  child.lua('vim.cmd("normal gtip")')
  local content = child.get_float_content()
  eq(true, content ~= nil and #content > 0, 'floating window should appear')
  local text = table.concat(content, '\n')
  eq(true, text:find('生活中') ~= nil, 'should contain Chinese query')
  eq(true, text:find('Sometimes') ~= nil, 'should contain English translation')
end

T['operator']['visual mode v gt'] = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.load_module()
      child.set_lines({ 'hello world and more words here' })
      child.set_cursor(1, 0)
    end,
  },
})
T['operator']['visual mode v gt']['translates visual selection'] = function()
  child.lua([[
    vim.cmd("normal! v5l")
    vim.cmd("normal! \027")
    require('kd-translator').operator('visual')
  ]])
  local content = child.get_float_content()
  eq(true, content ~= nil and #content > 0, 'floating window should appear')
  local text = table.concat(content, '\n')
  eq(true, text:find('hello') ~= nil, 'should contain selected word')
end

T['operator']['visual mode V gt'] = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.load_module()
      child.set_lines({
        'this is the first line something',
        'and the second line continues',
        'the third line also selected',
        '',
        'not selected',
      })
      child.set_cursor(1, 1)
    end,
  },
})
T['operator']['visual mode V gt']['translates line selection'] = function()
  child.lua([[
    vim.api.nvim_buf_set_mark(0, '<', 1, 0, {})
    vim.api.nvim_buf_set_mark(0, '>', 3, 0, {})
    require('kd-translator').operator('visual')
  ]])
  local content = child.get_float_content()
  eq(true, content ~= nil and #content > 0, 'floating window should appear')
  local text = table.concat(content, '\n')
  eq(true, text:find('something') ~= nil, 'should contain selected line text')
end

-- ====================================================================
-- Screenshots
-- ====================================================================
T['screenshots'] = new_set()

T['screenshots']['word result'] = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.load_module()
      child.set_lines({ 'hello' })
    end,
  },
})
T['screenshots']['word result']['matches reference'] = function()
  child.lua('vim.cmd("normal gtiw")')
  local content = child.get_float_content()
  eq(true, content ~= nil and #content > 0, 'floating window should appear')
  child.expect_screenshot('tests/screenshots/word-result', { ignore_text = true })
end

T['screenshots']['paragraph result'] = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.load_module()
      child.set_lines({
        '有时候，生活中总有些东西在等待着我们去发现。',
        '它可能是一个新的想法，也可能是一段新的经历。',
        '无论是什么，都值得我们去追寻。',
      })
      child.set_cursor(1, 1)
    end,
  },
})
T['screenshots']['paragraph result']['matches reference'] = function()
  child.lua('vim.cmd("normal gtip")')
  local content = child.get_float_content()
  eq(true, content ~= nil and #content > 0, 'floating window should appear')
  child.expect_screenshot('tests/screenshots/paragraph-result', { ignore_text = true })
end

return T

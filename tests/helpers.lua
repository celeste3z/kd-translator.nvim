local Helpers = {}

function Helpers.new_child_neovim()
  local child = MiniTest.new_child_neovim()

  child.setup = function()
    child.restart({ '-u', 'scripts/minimal_init.lua' })
    child.bo.readonly = false
    child.o.columns = 80
    child.o.lines = 24
  end

  child.load_module = function(config)
    local cfg = vim.tbl_deep_extend('force', { cmd = './tests/mock-kd' }, config or {})
    child.lua([[require('kd_translator').setup(...)]], { cfg })
    child.lua([[
      vim.keymap.set('n', 'gt', '<Plug>(kd-translator-operator)', { desc = 'Test' })
      vim.keymap.set('x', 'gt', '<Plug>(kd-translator-visual)', { desc = 'Test' })
    ]])
  end

  child.set_lines = function(lines)
    if type(lines) == 'string' then lines = vim.split(lines, '\n') end
    child.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  end

  child.set_cursor = function(line, col) child.api.nvim_win_set_cursor(0, { line, col }) end

  child.get_float_content = function(timeout)
    timeout = timeout or 3000
    child.lua(string.format(
      [[
      vim.wait(%d, function()
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_config(win).relative ~= ""
            and vim.api.nvim_win_get_config(win).relative ~= "editor"
          then
            return true
          end
        end
        return false
      end, 50)
    ]],
      timeout
    ))
    return child.lua([[
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local c = vim.api.nvim_win_get_config(win)
        if c.relative ~= "" and c.relative ~= "editor" then
          return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
        end
      end
      return {}
    ]])
  end

  child.expect_screenshot = function(path, opts)
    opts = opts or {}
    child.lua('vim.o.columns = 80')
    child.lua('vim.o.lines = 24')
    local screenshot = child.get_screenshot()
    local expect_opts = {}
    if opts.force then expect_opts.force = true end
    if opts.ignore_text ~= nil then expect_opts.ignore_text = opts.ignore_text end
    if opts.ignore_attr ~= nil then expect_opts.ignore_attr = opts.ignore_attr end
    MiniTest.expect.reference_screenshot(screenshot, path, expect_opts)
  end

  return child
end

Helpers.expect = MiniTest.expect
Helpers.new_set = MiniTest.new_set

return Helpers

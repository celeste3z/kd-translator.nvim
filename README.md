# kd-translator.nvim

Neovim plugin for [kd](https://github.com/Karmenzind/kd) CLI dictionary.
Translate words and paragraphs via `kd --json` / `kd -t` with rich formatting in a floating preview window.

## Features

- Word translation with phonetic, definitions, level, examples
- Paragraph translation
- Floating preview window with highlights
- Operator-pending mode (e.g. `gtiw`, `gtip`)
- Dot-repeat support via [vim-repeat](https://github.com/tpope/vim-repeat)
- Fully customizable formatting via hooks
- Dictionary complete integration

## Requirements

- Neovim >= 0.12
- [kd](https://github.com/Karmenzind/kd) CLI
- Optional: [vim-repeat](https://github.com/tpope/vim-repeat)

## Installation

### vim-pack

require `nvim-0.12`

```lua
vim.pack.add({ { src = 'https://github.com/celeste3z/kd-translator.nvim' } })

require('kd-translator').setup()

-- Optional: create gt keymaps
vim.keymap.set('n', 'gt', '<Plug>(kd-translator-operator)', { desc = 'Kd Translate Operator' })
vim.keymap.set('x', 'gt', '<Plug>(kd-translator-visual)', { desc = 'Kd Translate Visual' })
```

### lazy.nvim

```lua
{
  'celeste3z/kd-translator.nvim',
  opts = {},
  -- Optional: create gt keymaps
  keys = {
    { 'gt', desc = 'Kd Translate Operator', mode = 'n' },
    { 'gt', desc = 'Kd Translate Visual',   mode = 'x' },
  },
}
```

## Configuration

```lua
require('kd-translator').setup({
  cmd = 'kd',
  preview_opts = {
    border = 'rounded',
    title = ' Translator ',
    max_width = 80,
    max_height = 50,
  },
  hook = {
    pre_process = function(text) return text end,
    build_cmd = function(text) ... end,
    -- formatting hooks...
  },
})
```

See `:help kd-translator.txt` for all configuration options and hooks.

## Keymaps

The `gt` keymaps above give you:

- `gt` + motion → translate text object (e.g. `gtiw` for word, `gtip` for paragraph)
- `gt` in visual mode → translate selection

For quicker access, combine operator + motion:

```lua
vim.keymap.set('n', '<Leader>tw', '<Plug>(kd-translator-operator)iw')
vim.keymap.set('n', '<Leader>tp', '<Plug>(kd-translator-operator)ip')
vim.keymap.set('x', '<Leader>t', '<Plug>(kd-translator-visual)')
```

Press the same keybinding again (e.g. `gtiw` or `<Leader>tw`) to return focus to the preview window.

If [vim-repeat](https://github.com/tpope/vim-repeat) is installed:

- Pressing `.` after translation re-enters the preview window.
- Dot-repeat works across motions: translate "hello" with `gtiw`, then move to "world" and press `.` to quickly translate it.
- Dot-repeat works for paragraphs: translate one paragraph with `gtip`, move to another and press `.`.

## Command

```
:KdTranslator
```

Translates word under cursor or visual selection.

Examples:

```
" Translate word under cursor:
:KdTranslator

" Translate visual selection:
:'<,'>KdTranslate
```

## Dictionary complete integration

Use `format_raw_word_output()` to convert raw `kd --json` output into formatted
lines and highlight ranges, then `render()` to apply them to a buffer.

Example with [`blink-cmp-dictionary`](https://github.com/Kaiser-Yang/blink-cmp-dictionary) for [`blink.cmp`](https://github.com/Saghen/blink.cmp) (inside `blink.cmp` `opts.sources.providers`):

```lua
dictionary = {
  module = "blink-cmp-dictionary",
  name = "Dict",
  min_keyword_length = 3,
  opts = {
    dictionary_files = { "path/to/your/dictionary.txt" },
    get_documentation = function(item)
      return {
        get_command = function() return "kd" end,
        get_command_args = function() return { "--json", item } end,
        resolve_documentation = function(output)
          local kd = require("kd-translator")
          local lines, ranges = kd.format_raw_word_output(output)
          if #lines == 0 then return nil end
          return {
          draw = function(opts)
            kd.render(opts.window:get_buf(), lines, ranges)
          end,
          }
        end,
      }
    end,
  },
},
```

[`blink-cmp-dictionary`](https://github.com/Kaiser-Yang/blink-cmp-dictionary) provides dictionary word completions for [`blink.cmp`](https://github.com/Saghen/blink.cmp).
When a completion item is selected, `kd --json <word>` runs automatically and
the result renders with kd-translator's formatting in the documentation popup.

## Acknowledgments

- [mini.nvim](https://github.com/nvim-mini/mini.nvim) — operator implementation reference, [mini.doc](https://github.com/nvim-mini/mini.nvim) and [mini.test](https://github.com/nvim-mini/mini.nvim) for documentation generation and testing framework.

## License

MIT

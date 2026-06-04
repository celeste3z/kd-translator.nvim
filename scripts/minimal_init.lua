vim.cmd([[let &rtp = getcwd() .. ',' .. &rtp]])

-- Load mini.test and mini.doc if available via packpath
pcall(vim.cmd, 'packadd mini.nvim')
pcall(vim.cmd, 'packadd mini.test')
pcall(vim.cmd, 'packadd mini.doc')

vim.o.columns = 80
vim.o.lines = 24
vim.o.winborder = 'rounded'
vim.cmd('set notimeout nottimeout')
vim.o.background = 'dark'
vim.cmd('colorscheme habamax')
vim.o.termguicolors = true
vim.o.statusline = '%<%f %l,%c%V'
vim.cmd('au FileType lua set foldmethod=manual')

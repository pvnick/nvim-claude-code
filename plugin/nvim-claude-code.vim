" nvim-claude-code plugin initialization
" This file is automatically loaded by Neovim's plugin system

" Prevent loading the plugin multiple times
if exists('g:loaded_nvim_claude_code')
  finish
endif
let g:loaded_nvim_claude_code = 1

" Define the main command that users can call manually
" :ClaudeCode will trigger the same functionality as <leader>CC
command! ClaudeCode lua require('nvim-claude-code').run()

" Set up the default keymap for easy access
" <leader>CC opens the Claude Code input prompt
nnoremap <leader>CC :ClaudeCode<CR>
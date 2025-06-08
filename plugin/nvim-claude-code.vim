if exists('g:loaded_nvim_claude_code')
  finish
endif
let g:loaded_nvim_claude_code = 1

command! ClaudeCode lua require('nvim-claude-code').run()

nnoremap <leader>CC :ClaudeCode<CR>
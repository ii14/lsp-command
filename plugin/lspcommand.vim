function! s:comp(ArgLead, CmdLine, CursorPos)
  return luaeval('require"lspcommand".comp(_A[1], _A[2], _A[3])', [
    \ a:ArgLead, a:CmdLine, a:CursorPos,
    \ ])
endfunction

command! -bar -range=% -nargs=+ -complete=customlist,s:comp Lsp
  \ call luaeval('require"lspcommand".run(_A)', {
  \   'args': <q-args>, 'range': <range>, 'line1': <line1>, 'line2': <line2>,
  \ })

if !get(g:, 'lsp_no_lowercase', v:false)
  cnoreabbrev <expr> lsp getcmdtype() ==# ':' &&
    \ (getcmdline() ==# 'lsp' <bar><bar> getcmdline() ==# "'<,'>lsp") ? 'Lsp' : 'lsp'
endif

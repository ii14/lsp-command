if !get(g:, 'lsp_legacy_commands', v:false)
  silent! delcommand LspInfo
  silent! delcommand LspStart
  silent! delcommand LspStop
  silent! delcommand LspRestart
endif

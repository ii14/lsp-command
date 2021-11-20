# lsp-command

Command interface for neovim LSP.

Provides full access to LSP features with a single `:Lsp` command. To give few examples,
instead of `:lua vim.lsp.buf.workspace_symbol('foo')`, you can simply write `:Lsp find foo`.
To format a range of lines, make a visual selection and write `:Lsp format` (or
abbreviate it to just `:Lsp f`). `lspconfig` commands are now subcommands for `:Lsp`:
`:LspInfo` is now `:Lsp info`/`:Lsp?`, `:LspStart` is `:Lsp start` etc.

Completion for `:Lsp` command is contextual. Only completions valid in the current
context are suggested. That is, if the current buffer is not attached to any server, the
only completions will be `info`, `start`, `stop`, `restart`. If buffer is attached, only
actions supported by the attached language server are suggested.

Custom commands in vim have to start with an uppercase letter, but this plugin goes around
it by defining a basic command line abbreviation, or an alias, from the lowercase `:lsp`.
This means all of the examples above can be also written as without capitalizing the first
letter: `:lsp find foo`, `:lsp format`, `:lsp info` etc.

The interface is not final. Command names, their arguments and how they can be abbreviated
can change at any time.

Requires `neovim/lspconfig`.

## Usage

[`:h :Lsp`](doc/lsp-command.txt)

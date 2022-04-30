local fn = vim.fn

local function echo(msg)
  vim.api.nvim_echo({{msg}}, false, {})
  return nil
end

local function echoerr(msg)
  vim.api.nvim_echo({{'Lsp: '..msg, 'ErrorMsg'}}, true, {})
  return nil
end

local function complete_filter(arglead, candidates)
  if not candidates then
    return {}
  end
  arglead = arglead or ''

  local results = {}
  for _, k in ipairs(candidates) do
    if fn.stridx(k, arglead) == 0 then
      table.insert(results, k)
    end
  end
  return results
end

local function complete_active_clients(args)
  return complete_filter(args[#args], vim.tbl_map(function(client)
    return ("%d (%s)"):format(client.id, client.name)
  end, vim.lsp.get_active_clients()))
end

local function parse_clients(args)
  local clients = {}
  for _, arg in ipairs(args) do
    if arg:match('^%d+$') then
      local client = vim.lsp.get_client_by_id(tonumber(arg))
      if client == nil then
        return echoerr('No client with id '..arg)
      end
      clients[arg] = client
    elseif not arg:match('^%([%w_%-]+%)$') then
      return echoerr('Invalid argument: '..arg)
    end
  end

  if vim.tbl_isempty(clients) then
    return vim.lsp.get_active_clients()
  end
  return vim.tbl_values(clients)
end

local function simple_command(name, func, capability)
  return {
    command = name,
    attached = true,
    range = false,
    run = function(args)
      if #args ~= 0 then
        return echoerr('No arguments allowed')
      end
      func()
    end,
    capability = capability,
  }
end

local definition     = simple_command('definition', vim.lsp.buf.definition, 'definition')
local declaration    = simple_command('declaration', vim.lsp.buf.declaration, 'declaration')
local typedefinition = simple_command('typedefinition', vim.lsp.buf.type_definition, 'type_definition')
local symbols        = simple_command('symbols', vim.lsp.buf.document_symbol, 'document_symbol')
local hover          = simple_command('hover', vim.lsp.buf.hover, 'hover')
local implementation = simple_command('implementation', vim.lsp.buf.implementation, 'implementation')
local references     = simple_command('references', vim.lsp.buf.references, 'references')
local signature      = simple_command('signature', vim.lsp.buf.signature_help, 'signature_help')
local incomingcalls  = simple_command('incomingcalls', vim.lsp.buf.incoming_calls, 'call_hierarchy')
local outgoingcalls  = simple_command('outgoingcalls', vim.lsp.buf.outgoing_calls, 'call_hierarchy')

local rename = {
  command = 'rename',
  attached = true,
  range = false,
  run = function(args)
    if #args > 1 then
      return echoerr('Expected zero or one argument')
    end
    vim.lsp.buf.rename(args[1])
  end,
  capability = 'rename',
}

local find = {
  -- TODO: different name? "symbols" is used by document_symbol
  command = 'find',
  attached = true,
  range = false,
  run = function(args)
    if #args > 1 then
      return echoerr('Expected zero or one argument')
    end
    vim.lsp.buf.workspace_symbol(args[1] or '')
  end,
  capability = 'workspace_symbol',
}

local codeaction = {
  command = 'codeaction',
  attached = true,
  -- TODO: would be cool to provide a /pattern/ to filter code actions
  run = function(args, range)
    if #args > 1 then
      return echoerr('Expected zero or one argument')
    end
    local context = { only = args[1] }
    if range then
      vim.lsp.buf.range_code_action(context, range[1], range[2])
    else
      vim.lsp.buf.code_action(context)
    end
  end,
  complete = function(args)
    if #args == 1 then
      local kinds = {}
      for _, client in pairs(vim.lsp.buf_get_clients()) do
        local code_action = client.resolved_capabilities.code_action
        if type(code_action) == 'table' then
          for _, kind in ipairs(code_action.codeActionKinds) do
            kinds[kind] = true
          end
        end
      end
      return complete_filter(args[#args], vim.tbl_keys(kinds))
    end
  end,
  capability = 'code_action',
}

local format = {
  command = 'format',
  attached = true,
  run = function(args, range)
    -- TODO: FormattingOptions
    local sync, order
    local function parse_arg(arg)
      if arg == 'sync' then
        sync = true
        return true
      end

      local match = arg:match('^sync=(%d+)$')
      if match then
        sync = tonumber(match)
        return true
      end

      match = arg:match('^order=([%w_%-,]+)$')
      if match then
        order = vim.split(match, ',', { trimempty = true, plain = true })
        return true
      end
    end

    for _, arg in ipairs(args) do
      if not parse_arg(arg) then
        return echoerr('Invalid argument: '..arg)
      end
    end

    if order and not sync then
      sync = true
    end

    if sync then
      if range then
        return echoerr('Range not allowed for synchronous formatting')
      end

      if sync == true then
        sync = nil
      end

      if order then
        vim.lsp.buf.formatting_seq_sync(nil, sync, order)
      else
        vim.lsp.buf.formatting_sync(nil, sync)
      end
    else
      if range then
        vim.lsp.buf.range_formatting(nil, range[1], range[2])
      else
        vim.lsp.buf.formatting()
      end
    end
  end,
  complete = function(args)
    local arg = args[#args]
    local start, match = arg:match('^order=(.-)([^,]*)$')
    if start then
      local values = vim.split(start, ',', { trimempty = true, plain = true })
      local lookup = {}
      for _, k in ipairs(values) do
        lookup[k] = true
      end
      local results = {}
      for _, server in ipairs(require('lspconfig').available_servers()) do
        if not lookup[server] and fn.stridx(server, match) == 0 then
          table.insert(results, 'order='..start..server)
        end
      end
      return results
    else
      return complete_filter(arg, {'sync', 'order='})
    end
  end,
  capability = 'formatting', -- TODO: check range_formatting
}

local workspace = {
  command = 'workspace',
  range = false,
  attached = true,
  run = function(args)
    if #args == 0 then
      local folders = vim.lsp.buf.list_workspace_folders()
      if #folders > 0 then
        for _, folder in ipairs(folders) do
          echo(folder)
        end
      else
        echo('No workspace folders')
      end
    elseif #args == 2 then
      if args[1] == 'add' then
        vim.lsp.buf.add_workspace_folder(fn.fnamemodify(args[2], ':p'))
      elseif args[1] == 'remove' then
        vim.lsp.buf.remove_workspace_folder(args[2])
      else
        return echoerr('Invalid argument: '..args[1])
      end
    else
      return echoerr('Invalid arguments')
    end
  end,
  complete = function(args)
    if #args == 1 then
      return complete_filter(args[#args], {'add', 'remove'})
    elseif #args == 2 then
      if args[1] == 'add' then
        return fn.getcompletion(args[#args], 'dir')
      elseif args[1] == 'remove' then
        return complete_filter(args[#args], vim.lsp.buf.list_workspace_folders())
      end
    end
  end,
  capability = 'workspace',
}

local info = {
  command = 'info',
  range = false,
  run = function(args)
    if #args ~= 0 then
      return echoerr('No arguments allowed')
    end
    require('lspconfig/ui/lspinfo')()
  end,
}

local start = {
  command = 'start',
  range = false,
  run = function(args)
    if #args > 1 then
      return echoerr('Expected zero or one argument')
    end
    local server_name = args[1]
    local configs = require 'lspconfig/configs'
    if server_name then
      if configs[server_name] then
        configs[server_name].autostart()
      else
        return echoerr('Server not found: '..server_name)
      end
    else
      local buffer_filetype = vim.bo.filetype
      for _, config in pairs(configs) do
        for _, filetype_match in ipairs(config.filetypes or {}) do
          if buffer_filetype == filetype_match then
            config.autostart()
          end
        end
      end
    end
  end,
  complete = function(args)
    if #args == 1 then
      return complete_filter(args[#args], require('lspconfig').available_servers())
    end
  end,
}

local stop = {
  command = 'stop',
  range = false,
  run = function(args)
    local clients = parse_clients(args)
    if clients == nil then return end
    for _, client in ipairs(clients) do
      client.stop()
    end
  end,
  complete = complete_active_clients,
}

local restart = {
  command = 'restart',
  range = false,
  run = function(args)
    local clients = parse_clients(args)
    if clients == nil then return end
    for _, client in ipairs(clients) do
      local configs = require 'lspconfig/configs'
      client.stop()
      vim.defer_fn(function()
        configs[client.name].autostart()
      end, 500)
    end
  end,
  complete = complete_active_clients,
}


local commands = {
  codeaction,
  definition,
  declaration,
  typedefinition,
  symbols,
  hover,
  implementation,
  references,
  signature,
  rename,
  format,
  find,
  workspace,
  info,
  start,
  stop,
  restart,
  incomingcalls,
  outgoingcalls,
}

for _, command in ipairs(commands) do
  local name = command.command
  command.pattern = '\\V\\C\\^'..name:sub(1,1)..'\\%['..name:sub(2)..']\\$'
end

local function match_command(s)
  for _, command in ipairs(commands) do
    if fn.match(s, command.pattern) == 0 then
      return command
    end
  end
end


function _G._lsp_complete(ArgLead, CmdLine, CursorPos)
  local cmdline = fn.strpart(CmdLine, 0, CursorPos) -- trim cmdline to cursor position
  -- TODO: handle incomplete command name like ":Ls"
  --       also might not work with ":/Lsp /Lsp start"
  local begin = fn.match(cmdline, [[\v\C%(^|[^A-Za-z])\zsLsp%($|\s)]])
  if begin < 0 then return {} end
  local args = fn.split(fn.strpart(cmdline, begin)) -- split arguments
  if #args < 1 then return {} end

  local has_range = fn.strpart(CmdLine, 0, begin):match('%S') ~= nil
  local is_attached = false
  local capabilities = {}
  for _, client in pairs(vim.lsp.buf_get_clients(0)) do
    is_attached = true
    local c = client.resolved_capabilities
    if c.hover                     then capabilities.hover            = true end
    if c.goto_definition           then capabilities.definition       = true end
    if c.find_references           then capabilities.references       = true end
    if c.document_symbol           then capabilities.document_symbol  = true end
    if c.workspace_symbol          then capabilities.workspace_symbol = true end
    if c.document_formatting       then capabilities.formatting       = true end
    if c.document_range_formatting then capabilities.range_formatting = true end
    if c.call_hierarchy            then capabilities.call_hierarchy   = true end
    if c.rename                    then capabilities.rename           = true end
    if c.code_action               then capabilities.code_action      = true end
    if c.declaration               then capabilities.declaration      = true end
    if c.type_definition           then capabilities.type_definition  = true end
    if c.implementation            then capabilities.implementation   = true end
    if c.workspace                 then capabilities.workspace        = true end
    if c.signature_help            then capabilities.signature_help   = true end
  end

  -- remove first argument, "Lsp"
  table.remove(args, 1)
  -- add empty argument
  if CmdLine:sub(CursorPos, CursorPos):match('%s') then
    table.insert(args, '')
  end

  -- complete subcommand
  if #args < 2 then
    local results = {}
    for _, command in ipairs(commands) do
      if (command.range == nil or command.range == has_range) and
          (not command.attached or is_attached) and
          (not command.capability or capabilities[command.capability]) and
          fn.stridx(command.command, ArgLead) == 0 then
        table.insert(results, command.command)
      end
    end
    return results
  end

  -- complete for subcommand arguments
  local command = match_command(args[1])
  if not command or
      not (command.range == nil or command.range == has_range) or
      not (not command.attached or is_attached) then
    return {}
  end

  local complete = command.complete
  if complete then
    table.remove(args, 1)
    return complete(args)
  end
  return {}
end

function _G._lsp_command(ctx)
  local args = fn.split(ctx.args)
  if #args == 0 then
    return echoerr('Expected subcommand')
  end

  -- :Lsp?
  if ctx.args:match('%s*%?%s*') then
    return require('lspconfig/ui/lspinfo')()
  end

  local command = match_command(args[1])
  if command == nil then
    return echoerr('Invalid subcommand: '..args[1])
  end
  table.remove(args, 1)

  local range
  if ctx.range == 1 then
    range = {{ ctx.line1, 0 }, { ctx.line1, 0 }}
  elseif ctx.range == 2 then
    range = {{ ctx.line1, 0 }, { ctx.line2, 0 }}
  end
  if command.range == false and range ~= nil then
    return echoerr('No range allowed for '..command.command..' subcommand')
  end

  if command.attached == true then
    if not (function()
      for _ in pairs(vim.lsp.buf_get_clients(0)) do
        return true
      end
      return false
    end)() then
      return echoerr('Buffer not attached')
    end
  end

  command.run(args, range)
end


vim.cmd([[
  command! -bar -range=% -nargs=+ -complete=customlist,v:lua._lsp_complete Lsp
    \ call luaeval('_lsp_command(_A[1])', [{
    \   'args': <q-args>, 'range': <range>, 'line1': <line1>, 'line2': <line2>,
    \ }])
]])

local no_lowercase = vim.g.lsp_no_lowercase
if no_lowercase == nil or (no_lowercase ~= false and no_lowercase ~= 0) then
  -- TODO: better range matching
  vim.cmd([[
    cnoreabbrev <expr> lsp getcmdtype() ==# ':' &&
      \ (getcmdline() ==# 'lsp' <bar><bar> getcmdline() ==# "'<,'>lsp") ? 'Lsp' : 'lsp'
  ]])
end

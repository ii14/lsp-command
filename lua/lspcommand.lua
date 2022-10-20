local fn = vim.fn
local api = vim.api
local lsp = vim.lsp
local buf = lsp.buf

local function echo(msg)
  api.nvim_echo({{msg}}, false, {})
  return nil
end

local function echoerr(msg)
  api.nvim_echo({{'Lsp: '..msg, 'ErrorMsg'}}, true, {})
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
  end, lsp.get_active_clients()))
end

local function parse_clients(args)
  local clients = {}
  for _, arg in ipairs(args) do
    if arg:match('^%d+$') then
      local client = lsp.get_client_by_id(tonumber(arg))
      if client == nil then
        return echoerr('No client with id '..arg)
      end
      clients[arg] = client
    elseif not arg:match('^%([%w_%-]+%)$') then
      return echoerr('Invalid argument: '..arg)
    end
  end

  if vim.tbl_isempty(clients) then
    return lsp.get_active_clients()
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

local definition     = simple_command('definition',     buf.definition,      'definitionProvider')
local declaration    = simple_command('declaration',    buf.declaration,     'declarationProvider')
local typedefinition = simple_command('typedefinition', buf.type_definition, 'typeDefinitionProvider')
local symbols        = simple_command('symbols',        buf.document_symbol, 'documentSymbolProvider')
local hover          = simple_command('hover',          buf.hover,           'hoverProvider')
local implementation = simple_command('implementation', buf.implementation,  'implementationProvider')
local references     = simple_command('references',     buf.references,      'referencesProvider')
local signature      = simple_command('signature',      buf.signature_help,  'signatureHelpProvider')
local incomingcalls  = simple_command('incomingcalls',  buf.incoming_calls,  'callHierarchyProvider')
local outgoingcalls  = simple_command('outgoingcalls',  buf.outgoing_calls,  'callHierarchyProvider')

local rename = {
  command = 'rename',
  attached = true,
  range = false,
  run = function(args)
    if #args > 1 then
      return echoerr('Expected zero or one argument')
    end
    buf.rename(args[1])
  end,
  capability = 'renameProvider',
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
    buf.workspace_symbol(args[1] or '')
  end,
  capability = 'workspaceSymbolProvider',
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
      buf.range_code_action(context, range[1], range[2])
    else
      buf.code_action(context)
    end
  end,
  complete = function(args)
    if #args == 1 then
      local kinds = {}
      for _, client in pairs(lsp.buf_get_clients()) do
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
  capability = 'codeActionProvider',
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
        if buf.format then
          for _, name in pairs(order) do
            buf.format({ async = false, timeout_ms = sync, name = name })
          end
        else
          buf.formatting_seq_sync(nil, sync, order)
        end
      else
        if buf.format then
          buf.format({ async = false, timeout_ms = sync })
        else
          buf.formatting_sync(nil, sync)
        end
      end
    else
      if range then
        if buf.format then
          buf.format({ range = range })
        else
          buf.range_formatting(nil, range[1], range[2])
        end
      else
        if buf.format then
          buf.format({ async = true })
        else
          buf.formatting()
        end
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
  -- TODO: check documentRangeFormattingProvider
  capability = 'documentFormattingProvider',
}

local workspace = {
  command = 'workspace',
  range = false,
  attached = true,
  run = function(args)
    if #args == 0 then
      local folders = buf.list_workspace_folders()
      if #folders > 0 then
        for _, folder in ipairs(folders) do
          echo(folder)
        end
      else
        echo('No workspace folders')
      end
    elseif #args == 2 then
      if args[1] == 'add' then
        buf.add_workspace_folder(fn.fnamemodify(args[2], ':p'))
      elseif args[1] == 'remove' then
        buf.remove_workspace_folder(args[2])
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
        return complete_filter(args[#args], buf.list_workspace_folders())
      end
    end
  end,
  capability = 'workspaceFolders',
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


local function comp(ArgLead, CmdLine, CursorPos)
  local cmdline = fn.strpart(CmdLine, 0, CursorPos) -- trim cmdline to cursor position
  -- TODO: handle incomplete command name like ":Ls"
  --       also might not work with ":/Lsp /Lsp start"
  local begin = fn.match(cmdline, [[\v\C%(^|[^A-Za-z])\zsLsp%($|\s)]])
  if begin < 0 then return {} end
  local args = fn.split(fn.strpart(cmdline, begin)) -- split arguments
  if #args < 1 then return {} end

  local has_range = fn.strpart(CmdLine, 0, begin):match('%S') ~= nil
  local is_attached = false
  local caps = {}
  for _, client in pairs(lsp.buf_get_clients(0)) do
    is_attached = true
    for k, v in pairs(client.server_capabilities) do
      if v then
        caps[k] = true
      end
    end
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
          (not command.capability or caps[command.capability]) and
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

local function run(ctx)
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
      for _ in pairs(lsp.buf_get_clients(0)) do
        return true
      end
      return false
    end)() then
      return echoerr('Buffer not attached')
    end
  end

  command.run(args, range)
end

return {
  run = run,
  comp = comp,
}

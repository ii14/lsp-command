local fn = vim.fn

local function echoerr(msg)
  vim.api.nvim_echo({{'Lsp: '..msg, 'ErrorMsg'}}, true, {})
  return nil
end

local function complete_active_clients()
  return vim.tbl_map(function(client)
    return ("%d (%s)"):format(client.id, client.name)
  end, vim.lsp.get_active_clients())
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

local function wrap_simple_command(func)
  return function(args)
    if #args ~= 0 then
      return echoerr('No arguments allowed')
    end
    func()
  end
end

local commands = {}
local function define_command(command)
  table.insert(commands, command)
end


define_command{
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
    -- TODO: check server capabilities?
    if #args == 1 then
      return {
        'quickfix',
        'refactor',
        'refactor.extract',
        'refactor.inline',
        'refactor.rewrite',
        'source',
        'source.organizeImports',
        'source.fixAll',
      }
    end
  end,
}

define_command{
  command = 'definition',
  attached = true,
  range = false,
  run = wrap_simple_command(vim.lsp.buf.definition),
}

define_command{
  command = 'declaration',
  attached = true,
  range = false,
  run = wrap_simple_command(vim.lsp.buf.declaration),
}

define_command{
  command = 'symbols',
  attached = true,
  range = false,
  run = wrap_simple_command(vim.lsp.buf.document_symbol),
}

define_command{
  command = 'hover',
  attached = true,
  range = false,
  run = wrap_simple_command(vim.lsp.buf.hover),
}

define_command{
  command = 'implementation',
  attached = true,
  range = false,
  run = wrap_simple_command(vim.lsp.buf.implementation),
}

define_command{
  command = 'references',
  attached = true,
  range = false,
  run = wrap_simple_command(vim.lsp.buf.references),
}

define_command{
  command = 'signature',
  attached = true,
  range = false,
  run = wrap_simple_command(vim.lsp.buf.signature_help),
}

define_command{
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
  complete = function()
    return {'sync', 'order='}
  end,
}

define_command{
  command = 'info',
  range = false,
  run = function(args)
    if #args ~= 0 then
      return echoerr('No arguments allowed')
    end
    require('lspconfig/ui/lspinfo')()
  end,
}

define_command{
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
      return require('lspconfig').available_servers()
    end
  end,
}

define_command{
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

define_command{
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
  local is_attached = (function()
    for _ in ipairs(vim.lsp.buf_get_clients(0)) do
      return true
    end
    return false
  end)()

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
  if not complete then return {} end
  table.remove(args, 1)
  local completions = complete(args)
  if not completions then return {} end

  local results = {}
  for _, k in ipairs(completions) do
    if fn.stridx(k, ArgLead) == 0 then
      table.insert(results, k)
    end
  end
  return results
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
      for _ in ipairs(vim.lsp.buf_get_clients(0)) do
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

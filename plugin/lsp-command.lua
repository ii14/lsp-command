local fn = vim.fn

local function echoerr(msg)
  vim.api.nvim_echo({{msg, 'ErrorMsg'}}, true, {})
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
        return echoerr('Lsp: No client with id '..arg)
      end
      clients[arg] = client
    elseif not arg:match('^%([%w_%-]+%)$') then
      return echoerr('Lsp: Invalid argument: '..arg)
    end
  end

  if vim.tbl_isempty(clients) then
    return vim.lsp.get_active_clients()
  end
  return vim.tbl_values(clients)
end


local commands = {
  {
    command = 'info',
    run = function(args)
      if #args ~= 0 then
        return echoerr('Lsp: Expected zero arguments')
      end
      require('lspconfig/ui/lspinfo')()
    end,
  },
  {
    command = 'start',
    complete = function(args)
      if #args == 1 then
        return require('lspconfig').available_servers()
      end
    end,
    run = function(args)
      if #args > 1 then
        return echoerr('Lsp: Expected zero or one argument')
      end
      local server_name = args[1]
      local configs = require 'lspconfig/configs'
      if server_name then
        if configs[server_name] then
          configs[server_name].autostart()
        else
          return echoerr('Lsp: Server not found: '..server_name)
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
  },
  {
    command = 'stop',
    complete = complete_active_clients,
    run = function(args)
      local clients = parse_clients(args)
      if clients == nil then return end
      for _, client in ipairs(clients) do
        client.stop()
      end
    end,
  },
  {
    command = 'restart',
    complete = complete_active_clients,
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
  },
}


local function match_command(s)
  for _, command in ipairs(commands) do
    local name = command.command
    if fn.match(s, '\\V\\C\\^'..name:sub(1,1)..'\\%['..name:sub(2)..']\\$') == 0 then
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
          fn.stridx(command.command, ArgLead) == 0 then
        table.insert(results, command.command)
      end
    end
    return results
  end

  -- complete for subcommand arguments
  local command = match_command(args[1])
  if not command or not (command.range == nil or command.range == has_range) then
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
    return echoerr('Lsp: Expected subcommand')
  end
  local command = match_command(args[1])
  if command == nil then
    return echoerr('Lsp: Invalid subcommand: '..args[1])
  end
  table.remove(args, 1)
  command.run(args)
end


vim.cmd([[
  command! -bar -range=% -nargs=+ -complete=customlist,v:lua._lsp_complete Lsp
    \ call luaeval('_lsp_command(_A[1])', [{
    \   'args': <q-args>, 'range': <range>, 'line1': <line1>, 'line2': <line2>,
    \ }])
]])

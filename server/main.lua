-- server/main.lua
-- The gate. The picker is entirely client-side; all the server decides is who
-- is allowed to turn it on.

local function hasAce(source)
  if source == 0 then return true end

  for _, ace in ipairs(Config.AdminAce or {}) do
    if type(ace) == 'string' and ace ~= '' and IsPlayerAceAllowed(tostring(source), ace) then
      return true
    end
  end

  return false
end

RegisterCommand(Config.Command, function(source)
  if source == 0 then
    return print(('[tb_devtool] /%s is an in-game tool; run it from a client.'):format(Config.Command))
  end

  if not hasAce(source) then
    return TriggerClientEvent('ox_lib:notify', source, {
      title = Config.NotifyTitle,
      description = 'You do not have permission to use the dev tool.',
      type = 'error',
    })
  end

  TriggerClientEvent('tb_devtool:toggle', source)
end, false)

RegisterCommand(Config.ZoneCommand, function(source)
  if source == 0 then
    return print(('[tb_devtool] /%s is an in-game tool; run it from a client.'):format(Config.ZoneCommand))
  end

  if not hasAce(source) then
    return TriggerClientEvent('ox_lib:notify', source, {
      title = Config.NotifyTitle,
      description = 'You do not have permission to use the dev tool.',
      type = 'error',
    })
  end

  TriggerClientEvent('tb_devtool:zone', source)
end, false)

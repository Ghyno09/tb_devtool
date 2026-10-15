-- client/zonemode.lua
-- The zone builder: freecam, drop points, watch the shape close up, copy the
-- snippet. The point list and the snippets live in zone.lua and know nothing
-- about the game; this is the part that flies the camera and talks to the
-- panel.
--
-- Two threads for the same reason the picker has two: the probes yield, so a
-- loop that casts cannot also draw at frame rate.

local active = false
local focused = false
local state
local cursor

-- Any one of the controls bound to an action counts, so LMB and E are
-- interchangeable without the loop below caring which arrived.
local function pressed(action)
  for _, control in ipairs(Config.ZoneKeys[action] or {}) do
    if IsDisabledControlJustPressed(0, control) then return true end
  end
  return false
end

-- The direction the camera is looking, as a GTA heading. This is what a
-- vector4 in a coordinate list is for: where to face once you get there.
local function facing()
  local heading = GetFinalRenderedCamRot(2).z % 360.0
  return heading < 0.0 and heading + 360.0 or heading
end

local function notify(description, kind)
  lib.notify({
    title = Config.NotifyTitle,
    description = description,
    type = kind or 'inform',
  })
end

-- The panel is redrawn from the state after every change, accepted or
-- refused, so what you see is always what the builder actually holds rather
-- than what the last click hoped for.
local preview

local function clearPreview()
  if preview then
    pcall(function() preview:remove() end)
    preview = nil
  end
end

-- The wireframe shows the shape you are drawing; this is ox_lib rendering the
-- zone you would actually get from the snippet, walls and all. Rebuilt from
-- scratch on every change because a poly zone fixes its points at creation.
local function rebuildPreview()
  clearPreview()
  if not Config.ZonePreview or not Zone.isZone(state.format) or #state.points < 3 then return end

  local points = {}
  for i, point in ipairs(state.points) do
    points[i] = vec3(point.x, point.y, Zone.exportZ(state, point))
  end

  local ok, zone = pcall(lib.zones.poly, {
    points = points,
    thickness = state.thickness,
    debug = true,
  })
  preview = ok and zone or nil
end

local function push()
  rebuildPreview()

  local snippet, err = Zone.snippet(state)

  SendNUIMessage({
    type = 'zone:data',
    points = state.points,
    thickness = state.thickness,
    name = state.name,
    format = state.format,
    isZone = Zone.isZone(state.format),
    zOffset = state.zOffset,
    snippet = snippet,
    hint = err,
    focused = focused,
  })
end

local function apply(ok, message)
  if message then notify(message, ok and 'inform' or 'error') end
  push()
end

local function setFocus(value)
  focused = value
  SetNuiFocus(value, value)
  SendNUIMessage({ type = 'zone:focus', focused = value })
end

local function copySnippet()
  local snippet, err = Zone.snippet(state)
  if not snippet then return notify(err, 'error') end

  lib.setClipboard(snippet)
  notify(('Copied %d point%s.'):format(#state.points, #state.points == 1 and '' or 's'), 'success')
end

local function stop()
  if not active then return end
  active = false

  if focused then setFocus(false) end
  SendNUIMessage({ type = 'zone:close' })
  clearPreview()
  Freecam.stop()
  SendNUIMessage({ type = "controls:hide" })

  state, cursor = nil, nil
end

local function start()
  if active then return end

  active = true
  state = Zone.new()
  cursor = nil
  focused = false

  Freecam.start()
  SendNUIMessage({ type = 'zone:open' })
  push()

  SendNUIMessage({
    type = "controls",
    title = "Zone builder",
    items = {
      { keys = { "W", "A", "S", "D" },   label = "fly" },
      { keys = { "SPACE", "CTRL" },      label = "up / down" },
      { keys = { "SHIFT", "ALT" },       label = "faster / slower" },
      { keys = { "LMB", "E" },           label = "drop a point" },
      { keys = { "RMB", "Q" },           label = "undo the last" },
      { keys = { "SCROLL" },             label = "raise / lower Z" },
      { keys = { "G" },                  label = "use the panel" },
      { keys = { "ENTER" },              label = "copy snippet" },
      { keys = { "BACKSPACE" },          label = "exit" },
    },
  })

  -- Cast thread. Yields inside the probe, so it must not draw.
  CreateThread(function()
    while active do
      if focused then
        cursor = nil
      else
        local ok, cast = pcall(Ray.cast)
        cursor = (ok and cast and cast.hit) and cast.coords or nil
      end
      Wait(0)
    end
  end)

  -- Fly, draw and listen. Every frame.
  CreateThread(function()
    while active do
      for _, control in ipairs(Freecam.BLOCKED) do
        DisableControlAction(0, control, true)
      end

      -- While the panel has the mouse, flying would fight the cursor.
      if not focused then
        Freecam.update()
      end

      pcall(Render.zone, state.points, cursor, state.thickness, Zone.isZone(state.format), state.zOffset)

      if not focused then
        if pressed("exit") then
          break
        end

        if pressed("panel") then
          setFocus(true)
          push()
        end

        if pressed("addPoint") then
          apply(Zone.add(state, cursor, Config.ZoneMinSpacing, facing()))
        end

        if pressed("undoPoint") then
          apply(Zone.undo(state))
        end

        local step = IsDisabledControlPressed(0, 21) and Config.ZoneZFastStep or Config.ZoneZStep
        -- Silent on purpose. This fires once per scroll notch, and a toast
        -- per notch buries the screen in a stack of them within a second.
        -- The panel value and the markers in the world are the feedback.
        if pressed("raiseZ") then Zone.nudge(state, step) push() end
        if pressed("lowerZ") then Zone.nudge(state, -step) push() end

        if pressed("confirm") then
          copySnippet()
        end
      end

      Wait(0)
    end

    stop()
  end)
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

RegisterNUICallback('zone:blur', function(_, cb)
  cb('ok')
  if active and focused then
    setFocus(false)
    push()
  end
end)

RegisterNUICallback('zone:remove', function(data, cb)
  cb('ok')
  if active then apply(Zone.remove(state, tonumber(data and data.index) or 0)) end
end)

RegisterNUICallback('zone:move', function(data, cb)
  cb('ok')
  if active then
    apply(Zone.move(state, tonumber(data and data.index) or 0, tonumber(data and data.delta) or 0))
  end
end)

RegisterNUICallback('zone:clear', function(_, cb)
  cb('ok')
  if active then apply(Zone.clear(state)) end
end)

RegisterNUICallback('zone:thickness', function(data, cb)
  cb('ok')
  if not active then return end

  -- A zero or negative thickness makes a zone nothing can ever be inside, and
  -- the panel is a text box, so it can arrive as anything at all.
  local value = tonumber(data and data.thickness)
  if not value or value <= 0 then return apply(false, 'Thickness must be above zero.') end

  state.thickness = value
  push()
end)

RegisterNUICallback('zone:name', function(data, cb)
  cb('ok')
  if not active then return end

  local value = tostring(data and data.name or ''):gsub("['\"\n\r]", '')
  state.name = value ~= '' and value or 'zone'
  push()
end)

RegisterNUICallback("zone:zoffset", function(data, cb)
  cb("ok")
  if active then apply(Zone.setOffset(state, tonumber(data and data.zOffset))) end
end)

RegisterNUICallback("zone:format", function(data, cb)
  cb('ok')
  if not active then return end

  Zone.setFormat(state, data and data.format)
  push()
end)

RegisterNUICallback('zone:copy', function(_, cb)
  cb('ok')
  if active then copySnippet() end
end)

RegisterNUICallback('zone:close', function(_, cb)
  cb('ok')
  stop()
end)

RegisterNetEvent('tb_devtool:zone', function()
  if active then stop() else start() end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then stop() end
end)

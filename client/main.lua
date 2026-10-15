-- client/main.lua
-- The picker session. Two threads on purpose:
--
--   cast   the probes are asynchronous and yield until the engine answers, so
--          a loop that casts cannot also draw -- it would run at a fraction
--          of the frame rate and the beam would strobe.
--   draw   runs every frame off the last answer the cast thread left behind,
--          and owns input, so no keypress is missed while a probe resolves.
--
-- The ray maths lives in ray.lua and the drawing in render.lua; what is left
-- here is state, input and the clipboard.

local active = false
local format = Config.DefaultFormat
local current = { hit = false }

-- Held down for as long as the picker is up. The first group would otherwise
-- fire your weapon every time you click a prop; the rest are the vanilla
-- actions sitting on the keys the picker wants. Mouse look is deliberately
-- left alone -- turning the camera is how you aim.
local BLOCKED = {
  24, 25, 47, 58, 140, 141, 142, 257, 263, 264,  -- attack, aim, melee, throw
  38,   -- E picks things up
  44,   -- Q takes cover
  73,   -- X ducks
  74,   -- H is the headlight toggle
  177,  -- BACKSPACE
}

local function notify(description, kind)
  lib.notify({
    title = Config.NotifyTitle,
    description = description,
    type = kind or 'inform',
  })
end

-- A native missing from this build used to kill the whole frame thread on its
-- first pass and take the beam, the box and the readout with it, leaving
-- nothing on screen and no clue why. Now a bad step says so once, in F8 and
-- on a toast, and the rest of the frame carries on drawing.
local reported = {}
local function guard(label, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and not reported[label] then
    reported[label] = true
    print(('^1[tb_devtool] %s failed: %s^0'):format(label, tostring(err)))
    notify(('%s failed -- see F8 for the error.'):format(label), 'error')
  end
  return ok
end

-- Any one of the controls bound to an action counts, so the caller never has
-- to care whether LMB or E was the one pressed.
local function pressed(action)
  for _, control in ipairs(Config.Keys[action] or {}) do
    if IsDisabledControlJustPressed(0, control) then return true end
  end
  return false
end

-- Exactly what you would paste into a config: a vector literal, not a table
-- and not JSON.
local function formatCoords(coords, heading)
  local number = ('%%.%df'):format(Config.Precision)
  local n = function(value) return number:format(value + 0.0) end

  if format == 'vector4' then
    return ('vector4(%s, %s, %s, %s)'):format(n(coords.x), n(coords.y), n(coords.z), n(heading or 0.0))
  end

  return ('vector3(%s, %s, %s)'):format(n(coords.x), n(coords.y), n(coords.z))
end

local function copy(text)
  lib.setClipboard(text)
  notify(('Copied: %s'):format(text), 'success')
end

-- The controls card, drawn by this resource's own NUI rather than ox_lib's
-- TextUI, so both modes look like the same tool instead of like a stock
-- widget with a list of keys in it.
local function showLegend()
  SendNUIMessage({
    type = "controls",
    title = "Prop picker",
    items = {
      { keys = { "LMB", "E" },   label = "the prop's own coords" },
      { keys = { "RMB", "Q" },   label = "the exact spot you are aiming at" },
      { keys = { "X" },          label = format },
      { keys = { "H" },          label = "why will this not select?" },
      { keys = { "BACKSPACE" },  label = "exit" },
    },
  })
end

-- Dumps every probe, unfiltered, to F8. When a prop refuses to resolve this
-- is what separates "raise EntityPassTolerance" from "that thing has no
-- entity handle at all" -- guessing between those two wasted a lot of time.
local function diagnose()
  notify('Probing -- see F8.', 'inform')
  print('^3[tb_devtool] ---- diagnostic ----^0')

  local ok, rows = pcall(Ray.diagnose)
  if not ok then
    return print(('^1[tb_devtool] diagnostic failed: %s^0'):format(tostring(rows)))
  end

  for _, row in ipairs(rows) do
    if row.snap then
      print(("^3[tb_devtool]   %-22s probe z=%.3f  ground z=%.3f  delta=%s^0"):format(
        row.label, row.raw, row.z, row.delta and ("%.3f"):format(row.delta) or "none"))
    elseif row.missing then
      print(('^3[tb_devtool]   %-22s unavailable on this build^0'):format(row.label))
    elseif not row.hit then
      print(('^3[tb_devtool]   %-22s no hit^0'):format(row.label))
    else
      print(('^3[tb_devtool]   %-22s hit at %6.2fm  entityHit=%s  resolved=%s^0'):format(
        row.label, row.distance, tostring(row.raw), tostring(row.resolved)))
    end
  end

  print(('^3[tb_devtool]   tolerance=%.2f  flags=%d/%d^0'):format(
    Config.EntityPassTolerance, Config.RayFlags, Config.RayFlagsEntityOnly))

  -- The highlight half. A prop can resolve perfectly and still refuse to be
  -- boxed, which looks identical in game to not being found at all.
  local drew, highlight = pcall(Render.diagnose, current and current.entity)
  if drew then
    for _, row in ipairs(highlight) do
      print(("^3[tb_devtool]   %-22s %s^0"):format(row.label, row.value))
    end
  else
    print(("^1[tb_devtool]   highlight diagnostic failed: %s^0"):format(tostring(highlight)))
  end
  print('^3[tb_devtool] -------------------^0')
end

local function stop()
  if not active then return end
  active = false
  current = { hit = false }
  Render.clear()
  SendNUIMessage({ type = "controls:hide" })
  Render.hideStatus()
end

local function start()
  if active then return end
  active = true
  current = { hit = false }
  showLegend()

  -- Cast thread. Yields inside every probe, so it must not draw.
  CreateThread(function()
    while active do
      local ok, cast = pcall(Ray.cast)

      if ok then
        current = cast
      else
        current = { hit = false }
        if not reported.cast then
          reported.cast = true
          print(('^1[tb_devtool] ray cast failed: %s^0'):format(tostring(cast)))
          notify('Ray cast failed -- see F8 for the error.', 'error')
        end
      end

      Wait(0)
    end
  end)

  -- Draw and input thread. Every frame, off whatever the cast thread last
  -- left in `current`.
  CreateThread(function()
    while active do
      for _, control in ipairs(BLOCKED) do
        DisableControlAction(0, control, true)
      end

      local cast = current

      guard('beam', Render.beam, cast)
      guard('box', Render.box, cast.entity)
      guard('outline', Render.outline, cast.entity)
      guard('crosshair', Render.crosshair, cast)
      guard('status', Render.status, cast, format)

      if pressed('exit') then
        notify('Picker closed.')
        break
      end

      if pressed('toggleFormat') then
        format = format == 'vector4' and 'vector3' or 'vector4'
        showLegend()
      end

      if pressed('diagnose') then
        diagnose()
      end

      if pressed('copyEntity') then
        if not cast.hit then
          notify('Nothing in range.', 'error')
        elseif not cast.entity then
          notify('No entity there -- press H to see why, or RMB for the surface point.', 'error')
        else
          copy(formatCoords(GetEntityCoords(cast.entity), GetEntityHeading(cast.entity)))
        end
      end

      if pressed('copySurface') then
        if not cast.hit then
          notify('Nothing in range.', 'error')
        else
          copy(formatCoords(cast.coords, GetEntityHeading(PlayerPedId())))
        end
      end

      Wait(0)
    end

    stop()
  end)
end

RegisterNetEvent('tb_devtool:toggle', function()
  if active then
    stop()
    notify('Picker closed.')
  else
    start()
  end
end)

-- A restart mid-session would otherwise leave the last prop outlined and the
-- legend stuck on screen with nothing left to close it.
AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then stop() end
end)

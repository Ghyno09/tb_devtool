-- client/freecam.lua
-- A detached camera you fly with WASD. Standalone on purpose: rhys_tuning has
-- one, but it is a paid resource and this should not depend on it being
-- installed.
--
-- Nothing else needs to know the camera exists. Ray.direction already reads
-- GetFinalRenderedCamRot, which follows a scripted camera, so the picker and
-- the zone builder aim through this without a line of change.

Freecam = {}

local sin, cos, rad, sqrt = math.sin, math.cos, math.rad, math.sqrt

local cam
local running = false
local position = vector3(0.0, 0.0, 0.0)
local pitch, yaw = 0.0, 0.0

local function normalise(v)
  local length = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
  if length == 0.0 then return vector3(0.0, 0.0, 0.0) end
  return vector3(v.x / length, v.y / length, v.z / length)
end

local function forwardVector()
  local p, y = rad(pitch), rad(yaw)
  local flat = math.abs(cos(p))
  return vector3(-sin(y) * flat, cos(y) * flat, sin(p))
end

function Freecam.active()
  return running
end

function Freecam.coords()
  return position
end

function Freecam.start()
  if running then return end

  position = GetFinalRenderedCamCoord()
  local rot = GetFinalRenderedCamRot(2)
  pitch, yaw = rot.x, rot.z

  cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
    position.x, position.y, position.z,
    pitch, 0.0, yaw,
    GetGameplayCamFov(), false, 2)

  SetCamActive(cam, true)
  RenderScriptCams(true, false, 0, true, false)

  local ped = PlayerPedId()
  FreezeEntityPosition(ped, true)
  SetEntityInvincible(ped, true)

  running = true
end

function Freecam.stop()
  if not running then return end
  running = false

  RenderScriptCams(false, false, 0, true, false)
  if cam then
    SetCamActive(cam, false)
    DestroyCam(cam, false)
    cam = nil
  end

  -- The world streams around the focus, not the player, while the camera is
  -- detached. Leave it set and the game keeps loading around wherever you
  -- stopped flying.
  ClearFocus()

  local ped = PlayerPedId()
  FreezeEntityPosition(ped, false)
  SetEntityInvincible(ped, false)
end

-- Call once per frame from the mode that owns the camera. Returns nothing;
-- everything it does is to the camera.
function Freecam.update()
  if not running or not cam then return end

  local sensitivity = Config.FreecamSensitivity or 5.0
  yaw = yaw - GetDisabledControlNormal(0, 1) * sensitivity
  pitch = pitch - GetDisabledControlNormal(0, 2) * sensitivity

  -- Past vertical the camera flips and the controls invert, which is
  -- disorienting enough to lose your place in a field of identical trees.
  if pitch > 89.0 then pitch = 89.0 elseif pitch < -89.0 then pitch = -89.0 end

  local speed = Config.FreecamSpeed or 8.0
  if IsDisabledControlPressed(0, 21) then speed = Config.FreecamFastSpeed or 26.0 end
  if IsDisabledControlPressed(0, 19) then speed = Config.FreecamSlowSpeed or 2.0 end

  local forward = forwardVector()
  local right = normalise(vector3(forward.y, -forward.x, 0.0))

  local move = vector3(0.0, 0.0, 0.0)
  if IsDisabledControlPressed(0, 32) then move = move + forward end
  if IsDisabledControlPressed(0, 33) then move = move - forward end
  if IsDisabledControlPressed(0, 34) then move = move - right end
  if IsDisabledControlPressed(0, 35) then move = move + right end
  if IsDisabledControlPressed(0, 22) then move = move + vector3(0.0, 0.0, 1.0) end
  if IsDisabledControlPressed(0, 36) then move = move - vector3(0.0, 0.0, 1.0) end

  position = position + (normalise(move) * (speed * GetFrameTime()))

  SetCamCoord(cam, position.x, position.y, position.z)
  SetCamRot(cam, pitch, 0.0, yaw, 2)

  -- Without this the world unloads the moment you fly any distance from your
  -- ped, and you end up placing zone points on terrain that is not there.
  SetFocusPosAndVel(position.x, position.y, position.z, 0.0, 0.0, 0.0)
end

-- Controls the camera consumes. The mode that owns it must disable these
-- every frame, or you fly and sprint and jump at the same time.
Freecam.BLOCKED = {
  1, 2,                    -- mouse look
  14, 15, 241, 242,        -- scroll wheel, which nudges the export height
  21, 19,                  -- LSHIFT fast, LALT slow
  22, 36,                  -- SPACE up, LCTRL down
  30, 31, 32, 33, 34, 35,  -- movement
  24, 25, 44, 37, 38,      -- the picking keys, so they do not also act
  47, 58, 140, 141, 142, 257, 263, 264,
  177, 191, 201,           -- backspace, enter
}

-- client/ray.lua
-- Turns where the camera is looking into what is in front of it, and decides
-- which of up to three probes to believe. The probes yield, so this must be
-- called from its own thread, never from the drawing loop.

Ray = {}

local sin, cos, rad, abs = math.sin, math.cos, math.rad, math.abs

-- A GTA rotation (pitch, roll, yaw in degrees) as a unit forward vector.
-- Unit length matters: anything else would scale MaxDistance, so the ray
-- would reach a different number of metres depending on where you looked.
-- Same formula ox_lib's raycast uses, which is a good sign it is right.
local function rotationToDirection(rot)
  local pitch, yaw = rad(rot.x), rad(rot.z)
  local flat = abs(cos(pitch))
  return vector3(-sin(yaw) * flat, cos(yaw) * flat, sin(pitch))
end

-- Straight out of the camera, dead centre. You aim this by turning, the same
-- way you aim a weapon. FinalRendered rather than Gameplay so it still
-- follows a scripted camera if anything else on the server takes one over.
function Ray.direction()
  return rotationToDirection(GetFinalRenderedCamRot(2))
end

local function endpoints()
  local origin = GetFinalRenderedCamCoord()
  return origin, origin + (Ray.direction() * Config.MaxDistance)
end

local function alive(entity)
  if not entity or entity == 0 then return false end
  local ok, exists = pcall(DoesEntityExist, entity)
  return (ok and exists) and true or false
end

local function result(origin, limit, hit, coords, entity)
  hit = (hit == 1 or hit == true) and coords ~= nil

  return {
    hit = hit,
    coords = coords,
    entity = alive(entity) and entity or nil,
    rawEntity = entity or 0,
    distance = hit and #(coords - origin) or math.huge,
    origin = origin,
    limit = limit,
  }
end

-- Every resource on this server that successfully highlights a map prop --
-- ox_target directly, rhys_tuning through ox_lib -- resolves it the same way:
-- an ASYNC StartShapeTestLosProbe, read back with the INCLUDING_MATERIAL
-- getter. This resource originally used the expensive synchronous probe and
-- the plain getter, picked to keep the beam from flickering, and got hit=true
-- with entityHit=0 on props those resources resolve without trouble. A
-- cosmetic preference is not worth a picker that cannot pick: go down the
-- path that demonstrably works and solve the flicker by drawing on a
-- different thread from the one that casts.
local function probe(flags)
  local origin, limit = endpoints()
  local hit, entity, coords = lib.raycast.fromCoords(origin, limit, flags, 4)
  return result(origin, limit, hit, coords, entity)
end

-- A hairline probe can pass between two bounds that very nearly touch, which
-- is one way a prop ends up unselectable no matter how you aim at it.
-- Sweeping a sphere down the same line is thicker and catches those. ox_lib
-- has no wrapper for it, so this repeats its wait-until-resolved loop.
local function sweptProbe(flags, radius)
  if type(StartShapeTestSweptSphere) ~= 'function' or (radius or 0) <= 0 then return nil end

  local origin, limit = endpoints()
  local ped = (cache and cache.ped) or PlayerPedId()

  local started, handle = pcall(StartShapeTestSweptSphere,
    origin.x, origin.y, origin.z,
    limit.x, limit.y, limit.z,
    radius, flags, ped, 4
  )
  if not started or not handle then return nil end

  -- Bounded, unlike ox_lib's: a probe that never resolves would otherwise
  -- hang the cast thread for the rest of the session.
  for _ = 1, 200 do
    local ok, retval, hit, coords, _, _, entity = pcall(GetShapeTestResultIncludingMaterial, handle)
    if not ok then return nil end
    if retval ~= 1 then return result(origin, limit, hit, coords, entity) end
    Wait(0)
  end

  return nil
end

-- GTA renders terrain from one mesh and collides it with another. On sand
-- they can be tens of centimetres apart, so a ray against the collision hands
-- back a z that looks like it is under the visible ground -- the same reason
-- a ped looks half-buried on a beach. GetGroundZFor_3dCoord returns the
-- collision height, which is where feet actually rest and where a prop should
-- sit.
--
-- Only bare ground is snapped, and only by a small amount. Aiming at a table
-- top or a roof must not drag the point down to the dirt underneath, and
-- neither must standing on a pier.
local function snapToGround(coords, entity)
  if not Config.SnapToGround or entity then return coords, nil end
  if type(GetGroundZFor_3dCoord) ~= "function" then return coords, nil end

  local ok, found, groundZ = pcall(GetGroundZFor_3dCoord, coords.x, coords.y, coords.z + 1.0, false)
  if not ok or not found or not groundZ then return coords, nil end

  local delta = groundZ - coords.z
  if math.abs(delta) > (Config.SnapMaxDrop or 1.0) then return coords, delta end

  return vector3(coords.x, coords.y, groundZ), delta
end

-- Applied on the way out of Ray.cast, whichever pass won, so the beam, the
-- markers and the copied number all agree. rawCoords keeps what the probe
-- actually said, for the diagnostic.
local function finish(pass)
  if pass.hit and pass.coords then
    pass.rawCoords = pass.coords
    pass.coords, pass.groundDelta = snapToGround(pass.coords, pass.entity)
  end
  return pass
end

-- Which pass to believe. Pure, so the rule can be pinned down in tests rather
-- than argued about in game.
--
-- The first pass asks about everything including the map, so it is the honest
-- answer for where the beam physically stops. But a prop's map bound often
-- answers first and answers with no entity. The later passes leave the map
-- out and find the prop.
--
-- One of those only wins if it lands at roughly the same place: the bounds on
-- a single prop are near each other, but a prop on the far side of a wall is
-- not, and must not beat the wall.
function Ray.choose(worldPass, otherPass, tolerance)
  if worldPass.entity then return worldPass end
  if not (otherPass and otherPass.hit and otherPass.entity) then return worldPass end

  if not worldPass.hit then return otherPass end
  if otherPass.distance <= worldPass.distance + (tolerance or 0.25) then return otherPass end

  return worldPass
end

-- Fires the ray and reports what it found. Yields: cast thread only.
--   hit       false means it reached MaxDistance untouched: nothing to copy
--   entity    nil on a hit means no entity could be resolved there
--   rejected  metres past the surface where an entity WAS found but was too
--             far behind it to trust, so the readout can say how close it came
function Ray.cast()
  local worldPass = probe(Config.RayFlags)
  if worldPass.entity then return finish(worldPass) end

  local passes = { probe(Config.RayFlagsEntityOnly) }

  local swept = sweptProbe(Config.RayFlagsEntityOnly, Config.SphereRadius)
  if swept then passes[#passes + 1] = swept end

  local nearestRejected
  for _, pass in ipairs(passes) do
    local chosen = Ray.choose(worldPass, pass, Config.EntityPassTolerance)
    if chosen.entity then return finish(chosen) end

    if pass.entity and pass.distance < (nearestRejected or math.huge) then
      nearestRejected = pass.distance
    end
  end

  if nearestRejected and worldPass.hit then
    worldPass.rejected = nearestRejected - worldPass.distance
  end

  return finish(worldPass)
end

-- Every pass, unfiltered, for the diagnostic key. When a prop still refuses
-- to resolve this is what says whether ANY probe saw an entity there, which
-- is the difference between "raise the tolerance" and "that thing genuinely
-- has no entity handle and never will".
function Ray.diagnose()
  local rows = {}

  local function add(label, pass)
    if not pass then
      rows[#rows + 1] = { label = label, missing = true }
      return
    end
    rows[#rows + 1] = {
      label = label,
      hit = pass.hit,
      distance = pass.distance,
      raw = pass.rawEntity,
      resolved = pass.entity,
      coords = pass.coords,
    }
  end

  local worldPass = probe(Config.RayFlags)
  add(("probe %d (all)"):format(Config.RayFlags), worldPass)
  add(('probe %d (no map)'):format(Config.RayFlagsEntityOnly), probe(Config.RayFlagsEntityOnly))
  add(("sphere %.2fm"):format(Config.SphereRadius or 0),
    sweptProbe(Config.RayFlagsEntityOnly, Config.SphereRadius))

  -- Where the collision mesh says the ground is, versus where the probe
  -- landed. On sand these disagree, and seeing both numbers is the whole
  -- explanation for "the coords went under the floor".
  if worldPass.hit and worldPass.coords then
    local snapped, delta = snapToGround(worldPass.coords, worldPass.entity)
    rows[#rows + 1] = {
      label = "ground snap",
      snap = true,
      raw = worldPass.coords.z,
      z = snapped.z,
      delta = delta,
    }
  end

  return rows
end

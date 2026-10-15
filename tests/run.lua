-- Minimal test runner, same shape as tb_priority's. Unlike that one this
-- resource's logic DOES need natives -- the ray reads the camera, the box
-- reads the model -- so the runner stubs them and lets the tests move the
-- stubs around. Crucially it can also make a native THROW, because natives
-- throwing rather than failing is this resource's recurring problem, and it
-- can script what each shapetest flag combination "sees", because which pass
-- finds the prop is the whole difficulty.
package.path = "./?.lua;" .. package.path

-- CfxLua's vector3, cut down to the operators ray.lua and render.lua use.
local V = {}
V.__index = V
local function vec3(x, y, z) return setmetatable({ x = x, y = y, z = z }, V) end
V.__add = function(a, b) return vec3(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return vec3(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b)
  if type(b) == "number" then return vec3(a.x * b, a.y * b, a.z * b) end
  return vec3(a * b.x, a * b.y, a * b.z)
end
V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
V.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
V.__tostring = function(a) return ("(%.3f, %.3f, %.3f)"):format(a.x, a.y, a.z) end
vector3 = vec3

dofile("config.lua")

Stub = {
  camRot = vec3(0, 0, 0),
  camPos = vec3(0, 0, 0),
  screenW = 1920,
  screenH = 1080,
  modelMin = vec3(-1, -2, 0),
  modelMax = vec3(1, 2, 3),
  entityPos = vec3(0, 0, 0),
  model = 12345,
  modelValid = true,
  entityType = 3,
  calls = {},
  lines = {},
  markers = {},
  throws = {},
  probes = {},
  groundFound = true,
  groundZ = nil,
  sphere = nil,
}

function Stub.aim(yaw, pitch)
  Stub.camRot = vec3(pitch or 0, 0, yaw or 0)
end

function Stub.reset()
  Stub.lines, Stub.markers, Stub.throws = {}, {}, {}
  Stub.probes, Stub.sphere = {}, nil
  Stub.groundFound, Stub.groundZ = true, nil
  Stub.model, Stub.modelValid = 12345, true
  Stub.entityType, Stub.calls = 3, {}
end

-- What a given flag combination finds. Distances are along +y, which is where
-- an unrotated camera looks, so `distance` and the y coordinate are the same
-- number and the tests stay readable.
function Stub.probe(flags, hit, entity, distance)
  Stub.probes[flags] = { hit = hit, entity = entity, distance = distance }
end

-- Natives on this build do not politely return nothing when they cannot cope;
-- they raise. Any stub can be told to do the same.
local function maybeThrow(name)
  if Stub.throws[name] then
    error(("native %s: exception at address gta-streaming-five.dll+2BD0E"):format(name), 0)
  end
end

function GetFinalRenderedCamRot() return Stub.camRot end
function GetFinalRenderedCamCoord() return Stub.camPos end
function GetGameplayCamRot() return Stub.camRot end
function GetGameplayCamCoord() return Stub.camPos end
function GetActiveScreenResolution() return Stub.screenW, Stub.screenH end
function PlayerPedId() return 1 end

function DoesEntityExist(entity)
  maybeThrow("DoesEntityExist")
  return entity ~= nil and entity ~= 0
end

function GetEntityModel()
  maybeThrow("GetEntityModel")
  return Stub.model
end

function IsModelValid()
  maybeThrow("IsModelValid")
  return Stub.modelValid
end

function GetModelDimensions()
  Stub.calls.GetModelDimensions = (Stub.calls.GetModelDimensions or 0) + 1
  maybeThrow("GetModelDimensions")
  return Stub.modelMin, Stub.modelMax
end

function GetEntityType()
  maybeThrow("GetEntityType")
  return Stub.entityType
end

-- Returns the COLLISION ground height, which on sand is not the height the
-- terrain is drawn at. Callers pass z + 1.0, so the default answer here has to
-- undo that to mean "no correction".
function GetGroundZFor_3dCoord(_, _, z)
  maybeThrow("GetGroundZFor_3dCoord")
  if not Stub.groundFound then return false, 0.0 end
  return true, Stub.groundZ ~= nil and Stub.groundZ or (z - 1.0)
end

function GetEntityCoords()
  maybeThrow("GetEntityCoords")
  return Stub.entityPos
end

function GetOffsetFromEntityInWorldCoords(_, x, y, z)
  return Stub.entityPos + vec3(x, y, z)
end

local handles, nextHandle = {}, 0

-- ox_lib, stubbed at the level the resource actually calls it. The real one
-- fires an async StartShapeTestLosProbe and reads it back with the
-- INCLUDING_MATERIAL getter; what matters to these tests is only which flag
-- combination sees which entity.
lib = {
  raycast = {
    fromCoords = function(_, _, flags)
      maybeThrow("raycast")
      local found = Stub.probes[flags]
      if not found or not found.hit then return false, 0, nil end
      return true, found.entity or 0, vec3(0, found.distance or 0, 0)
    end,
  },
}

cache = { ped = 1 }

function Wait() end

function StartShapeTestSweptSphere()
  maybeThrow("StartShapeTestSweptSphere")
  nextHandle = nextHandle + 1
  handles[nextHandle] = Stub.sphere
  return nextHandle
end

-- retval, hit, endCoords, surfaceNormal, materialHash, entityHit
function GetShapeTestResultIncludingMaterial(handle)
  local found = handles[handle]
  if not found or not found.hit then return 2, false, nil, vec3(0, 0, 0), 0, 0 end
  return 2, true, vec3(0, found.distance or 0, 0), vec3(0, 0, 0), 0, found.entity or 0
end

function DrawLine(x1, y1, z1, x2, y2, z2)
  Stub.lines[#Stub.lines + 1] = { a = vec3(x1, y1, z1), b = vec3(x2, y2, z2) }
end

function DrawMarker(_, x, y, z)
  Stub.markers[#Stub.markers + 1] = vec3(x, y, z)
end

T = { checks = 0, failed = 0 }

function T.near(got, want, tol, label)
  T.checks = T.checks + 1
  if math.abs(got - want) > (tol or 1e-3) then
    T.failed = T.failed + 1
    print(("  FAIL %s: got %.4f, want %.4f"):format(label or "?", got, want))
  end
end

function T.eq(got, want, label)
  T.checks = T.checks + 1
  if got ~= want then
    T.failed = T.failed + 1
    print(("  FAIL %s: got %s, want %s"):format(label or "?", tostring(got), tostring(want)))
  end
end

function T.ok(cond, label)
  T.checks = T.checks + 1
  if not cond then
    T.failed = T.failed + 1
    print("  FAIL " .. (label or "?"))
  end
end

local modules = { "client/ray.lua", "client/render.lua", "client/zone.lua" }
for _, path in ipairs(modules) do
  local f = io.open(path, "r")
  if f then f:close() dofile(path) end
end

local tests = { "tests/ray_test.lua", "tests/cast_test.lua", "tests/box_test.lua", "tests/zone_test.lua" }
for _, path in ipairs(tests) do
  local f = io.open(path, "r")
  if f then
    f:close()
    print("-- " .. path)
    dofile(path)
  end
end

if T.failed > 0 then
  print(("FAILED (%d of %d checks)"):format(T.failed, T.checks))
  os.exit(1)
end

print(("OK (%d checks)"):format(T.checks))

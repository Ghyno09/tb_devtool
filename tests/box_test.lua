-- The highlight. Two halves: the box geometry has to actually be a box, and
-- every native it leans on has to be allowed to explode without the highlight
-- disappearing, because on this build several of them do.

Stub.reset()
Render.box(nil)
T.eq(#Stub.lines, 0, "no entity draws nothing")

Stub.reset()
Stub.modelMin, Stub.modelMax = vector3(-1, -2, 0), vector3(1, 2, 3)
Stub.entityPos = vector3(0, 0, 0)
Render.box(1)
T.eq(#Stub.lines, 12, "a box has twelve edges")

-- Every corner of a cuboid meets exactly three edges. Any duplicate edge or
-- diagonal breaks this immediately.
local uses = {}
local function key(v) return ("%.3f,%.3f,%.3f"):format(v.x, v.y, v.z) end
for _, line in ipairs(Stub.lines) do
  uses[key(line.a)] = (uses[key(line.a)] or 0) + 1
  uses[key(line.b)] = (uses[key(line.b)] or 0) + 1
end

local corners = 0
for _, count in pairs(uses) do
  corners = corners + 1
  T.eq(count, 3, "each corner meets three edges")
end
T.eq(corners, 8, "a box has eight corners")

-- A cuboid's edges total 4*(width + depth + height). Diagonals are longer
-- than the sides they replace, so this catches them even if the count above
-- somehow passed.
local width = Stub.modelMax.x - Stub.modelMin.x
local depth = Stub.modelMax.y - Stub.modelMin.y
local height = Stub.modelMax.z - Stub.modelMin.z

local total = 0.0
for _, line in ipairs(Stub.lines) do total = total + #(line.b - line.a) end
T.near(total, 4 * (width + depth + height), 1e-3, "total edge length")

-- Every edge runs along exactly one axis: no edge may differ on two axes.
for i, line in ipairs(Stub.lines) do
  local delta = line.b - line.a
  local moved = 0
  if math.abs(delta.x) > 1e-6 then moved = moved + 1 end
  if math.abs(delta.y) > 1e-6 then moved = moved + 1 end
  if math.abs(delta.z) > 1e-6 then moved = moved + 1 end
  T.eq(moved, 1, ("edge %d runs along one axis"):format(i))
end

-- The box has to follow the prop, not sit at the world origin.
Stub.reset()
Stub.entityPos = vector3(120.5, -430.25, 62.0)
Render.box(1)
local minX, maxX = math.huge, -math.huge
for _, line in ipairs(Stub.lines) do
  minX = math.min(minX, line.a.x, line.b.x)
  maxX = math.max(maxX, line.a.x, line.b.x)
end
T.near(minX, Stub.entityPos.x + Stub.modelMin.x, 1e-3, "box tracks the entity on min x")
T.near(maxX, Stub.entityPos.x + Stub.modelMax.x, 1e-3, "box tracks the entity on max x")

-- A flat prop -- a sign, a decal -- collapses one axis to zero. It must still
-- produce a frame rather than dividing by anything.
Stub.reset()
Stub.modelMin, Stub.modelMax = vector3(-1, 0, -1), vector3(1, 0, 1)
Render.box(1)
T.eq(#Stub.lines, 12, "a zero-depth prop still draws twelve edges")
Stub.modelMin, Stub.modelMax = vector3(-1, -2, 0), vector3(1, 2, 3)

---------------------------------------------------------------------------
-- Natives that throw instead of failing.
---------------------------------------------------------------------------

-- GET_MODEL_DIMENSIONS raises inside gta-streaming on some map archetypes --
-- tree archetypes among them. The ray still finds the entity, so the
-- crosshair goes green, and then the highlight used to quietly draw nothing:
-- "why can't trees be highlighted". A post on the prop's origin is the
-- fallback, and it has to appear.
Stub.reset()
Stub.entityPos = vector3(10, 20, 30)
Stub.throws.GetModelDimensions = true
local ok = pcall(Render.box, 1)
T.ok(ok, "a throwing GetModelDimensions does not propagate")
T.eq(#Stub.markers, 2, "an unmeasurable prop gets a ring and a sphere")
T.near(Stub.markers[1].z, Stub.entityPos.z - 1.0, 1e-3, "the ring sits at the prop base")
T.near(Stub.markers[2].z, Stub.entityPos.z, 1e-3, "the sphere sits on the prop origin")
T.eq(#Stub.lines, 0, "the fallback marker draws no post line")
T.near(Stub.markers[1].x, 10, 1e-3, "the fallback marker sits on the prop")


-- Same contract for every other native the highlight touches.
for _, native in ipairs({ "GetEntityModel", "IsModelValid", "DoesEntityExist", "GetEntityCoords" }) do
  Stub.reset()
  Stub.throws[native] = true
  local survived = pcall(Render.box, 1)
  T.ok(survived, ("a throwing %s does not propagate"):format(native))
end

-- A model the streaming module rejects is not a crash, just unmeasurable.
Stub.reset()
Stub.modelValid = false
Render.box(1)
T.eq(#Stub.markers, 2, "an invalid model falls back to ring and sphere")

Stub.reset()
Stub.model = 0
Render.box(1)
T.eq(#Stub.markers, 2, "a zero model hash falls back to ring and sphere")

-- The bug that started all of this: SetEntityDrawOutlineColour does not exist
-- on this build, and calling a nil global killed the frame thread on its
-- first pass -- no beam, no box, no readout, and nothing to say why. The
-- runner leaves all three outline natives undefined on purpose, so these
-- calls run the same path that used to throw.
Stub.reset()
T.ok(SetEntityDrawOutline == nil, "the runner leaves the outline native missing")
T.ok(SetEntityDrawOutlineColour == nil, "the runner leaves the colour native missing")

local survived, err = pcall(Render.outline, 1)
T.ok(survived, "outline degrades quietly when the native is missing: " .. tostring(err))

survived, err = pcall(Render.clear)
T.ok(survived, "clear degrades quietly when the native is missing: " .. tostring(err))

Render.box(1)
T.eq(#Stub.lines, 12, "the box still draws with no outline native present")

---------------------------------------------------------------------------
-- Render.diagnose: the highlight half of the H key.
---------------------------------------------------------------------------

-- The case this was built for: the entity resolved perfectly, and the box
-- still cannot be drawn. The dump has to name which call refused, otherwise
-- "it will not highlight" and "it will not select" look identical in game.
Stub.reset()
Stub.throws.GetModelDimensions = true
local rows = Render.diagnose(2476034)

local byLabel = {}
for _, row in ipairs(rows) do byLabel[row.label] = row.value end

T.eq(byLabel.entity, "2476034", "the resolved entity is echoed back")
T.ok(byLabel.GetModelDimensions ~= nil, "the measuring step is reported")
T.ok(byLabel.GetModelDimensions:find("THREW"), "a throwing measure is named as throwing")
T.eq(byLabel.SetEntityDrawOutline, "false", "the missing outline native is reported")

-- The healthy case reports a size rather than an error, so the two are
-- distinguishable at a glance in F8.
Stub.reset()
Stub.modelMin, Stub.modelMax = vector3(-1, -2, 0), vector3(1, 2, 3)
rows = Render.diagnose(2476034)
byLabel = {}
for _, row in ipairs(rows) do byLabel[row.label] = row.value end
T.eq(byLabel.GetModelDimensions, "2.00 x 4.00 x 3.00", "a measurable prop reports its size")

-- No entity at all: say so, and point at the probe rows rather than printing
-- a wall of nils.
rows = Render.diagnose(nil)
T.eq(#rows, 1, "no entity produces a single row")
T.ok(rows[1].value:find("none resolved"), "and says nothing was resolved")

-- Diagnosing must never be the thing that breaks the session.
Stub.reset()
Stub.throws.GetEntityModel = true
T.ok(pcall(Render.diagnose, 1), "a throwing model lookup does not propagate")
Stub.reset()
Stub.throws.GetEntityType = true
T.ok(pcall(Render.diagnose, 1), "a throwing type lookup does not propagate")

-- Render.unmeasured drives the readout note, so it has to track reality.
Stub.reset()
Stub.throws.GetModelDimensions = true
Render.box(1)
T.eq(Render.unmeasured, true, "an unmeasurable prop is flagged for the readout")
Stub.reset()
Render.box(1)
T.eq(Render.unmeasured, false, "a measurable prop clears the flag again")

---------------------------------------------------------------------------
-- Peds. GetModelDimensions on a ped model does not raise something a pcall
-- can catch -- it takes the game down. These assert the native is never
-- REACHED, not merely that the call survived, because surviving is not what
-- happens.
---------------------------------------------------------------------------

Stub.reset()
Stub.entityType = 1                       -- ped
Render.box(1)
T.eq(Stub.calls.GetModelDimensions, nil, "a ped is never measured")
T.eq(#Stub.markers, 2, "a ped still gets the ring-and-sphere highlight")

Stub.reset()
Stub.entityType = 1
Render.outline(1)
T.ok(true, "outlining a ped does not error")

-- Pressing H while pointing at a ped must not be the thing that crashes you.
Stub.reset()
Stub.entityType = 1
local rows = Render.diagnose(1)
T.eq(Stub.calls.GetModelDimensions, nil, "diagnosing a ped never measures it")

local byLabel = {}
for _, row in ipairs(rows) do byLabel[row.label] = row.value end
T.ok(byLabel.GetModelDimensions:find("skipped"), "and says why it skipped")
T.ok(byLabel.SetEntityDrawOutline ~= nil, "while still reporting the rest of the rows")

-- Objects and vehicles are measured as before.
for _, kind in ipairs({ 2, 3 }) do
  Stub.reset()
  Stub.entityType = kind
  Render.box(1)
  T.eq(Stub.calls.GetModelDimensions, 1, ("entity type %d is measured"):format(kind))
  T.eq(#Stub.lines, 12, ("entity type %d gets a real box"):format(kind))
end

-- And the flags no longer invite peds into the ray in the first place.
T.eq(Config.RayFlags & 4, 0, "the main pass excludes PED")
T.eq(Config.RayFlags & 8, 0, "the main pass excludes RAGDOLL")
T.eq(Config.RayFlagsEntityOnly & 4, 0, "the entity-only pass excludes PED")
T.eq(Config.RayFlagsEntityOnly & 8, 0, "the entity-only pass excludes RAGDOLL")
T.eq(Config.RayFlags & 256, 256, "but foliage is still in, or trees break again")

-- client/render.lua
-- Everything you can see while the picker is up: the beam, the post and box
-- marking what it landed on, and the readout of what you are about to copy.
-- It is handed a cast result and draws it. It decides nothing.

Render = {}

-- Natives that are not safe to just call:
--   SetEntityDrawOutlineColour  does not exist on this build at all
--   GetEntityArchetypeName      throws inside extra-natives on map entities
--   GetModelDimensions          throws inside gta-streaming on some map
--                               archetypes rather than returning nothing
-- All three are optional decoration. Resolve them, never trust them, and let
-- the drawing degrade rather than take the frame thread down with it.
local drawOutline = SetEntityDrawOutline
local outlineColour = SetEntityDrawOutlineColour or SetEntityDrawOutlineColor
local archetypeName = GetEntityArchetypeName
local archetypeBroken = false

local outlined

local function normalise(v)
  local length = #v
  if length == 0.0 then return vector3(0.0, 0.0, 0.0) end
  return vector3(v.x / length, v.y / length, v.z / length)
end

local function cross(a, b)
  return vector3(
    a.y * b.z - a.z * b.y,
    a.z * b.x - a.x * b.z,
    a.x * b.y - a.y * b.x
  )
end

-- The beam wants to leave the hand, but a ped with no such bone hands back
-- its own origin instead, which drops the beam to the character's ankles.
-- Chest height is the better wrong answer.
local function beamOrigin(ped)
  local coords = GetEntityCoords(ped)
  local bone = GetPedBoneCoords(ped, Config.BeamBone, 0.0, 0.0, 0.0)
  if #(bone - coords) < 0.1 then
    return coords + vector3(0.0, 0.0, 0.6)
  end
  return bone
end

-- A sphere on the picked point. Deliberately just the sphere: rhys_tuning
-- draws a tall vertical post with its location markers, and in an orchard
-- that post is a red line up through the canopy that hides the thing you are
-- trying to look at.
local function marker(coords, colour, alpha, size)
  size = size or 0.18
  DrawMarker(28, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    size, size, size, colour.r, colour.g, colour.b, alpha or 160,
    false, false, 2, false, nil, nil, false)
end


-- For a prop the streaming module refuses to measure there is no box to
-- draw, and a lone sphere at its origin is far too quiet -- it reads as "not
-- detected" when the prop is in fact selected and ready to copy. A ring on
-- the ground plus a fat sphere is unmistakable without needing a size.
local function ring(coords, colour, radius)
  DrawMarker(1, coords.x, coords.y, coords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    radius, radius, 2.0, colour.r, colour.g, colour.b, 90,
    false, false, 2, false, nil, nil, false)
end
-- One DrawLine is a single pixel at any distance. Repeating it nudged around
-- its own axis costs nothing and gives a line you can actually follow across
-- a dark field. The offsets are in world space, so the beam is fatter close
-- up and tapers with distance, which reads correctly for a laser.
function Render.beam(cast)
  local from = beamOrigin(PlayerPedId())
  local to = cast.hit and cast.coords or cast.limit
  if not to then return end

  local colour = Config.BeamColour

  DrawLine(from.x, from.y, from.z, to.x, to.y, to.z, colour.r, colour.g, colour.b, 255)

  local direction = normalise(to - from)
  local side = normalise(cross(direction, vector3(0.0, 0.0, 1.0)))
  local up = cross(side, direction)

  for pass = 1, math.max(Config.BeamThickness or 1, 1) - 1 do
    local spread = 0.008 * pass
    for _, axis in ipairs({ side, up }) do
      for _, sign in ipairs({ 1.0, -1.0 }) do
        local offset = axis * (spread * sign)
        local a, b = from + offset, to + offset
        DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, colour.r, colour.g, colour.b, 255)
      end
    end
  end

  if cast.hit then
    marker(to, colour, 210)
  end
end

-- Measuring a prop means asking the streaming module about its archetype, and
-- for some map archetypes that call does not fail, it throws. Every step gets
-- checked, and a prop that cannot be measured simply is not boxed.
-- Entity types: 1 ped, 2 vehicle, 3 object. Handing a PED model to
-- GetModelDimensions does not raise something a pcall can catch -- it takes
-- the game down. Config.RayFlags already leaves peds out of the ray; this is
-- the second lock on the same door, because the cost of getting it wrong is a
-- crash rather than a line in F8.
local MEASURABLE = { [2] = true, [3] = true }

local function measurable(entity)
  local ok, kind = pcall(GetEntityType, entity)
  return (ok and MEASURABLE[kind]) and true or false
end

local function dimensions(entity)
  if not measurable(entity) then return nil end

  local gotModel, model = pcall(GetEntityModel, entity)
  if not gotModel or not model or model == 0 then return nil end

  local gotValid, valid = pcall(IsModelValid, model)
  if not gotValid or not valid then return nil end

  local gotSize, min, max = pcall(GetModelDimensions, model)
  if not gotSize or not min or not max then return nil end

  return min, max
end

-- Corners 1-4 are the bottom face and 5-8 the top, each above its neighbour,
-- which is what lets the edge list below stay this short.
local EDGES = {
  { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 },
  { 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 },
  { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },
}

-- A wireframe box around the prop, built from the model's own bounding box
-- and transformed through the entity, so it sits at the prop's rotation
-- rather than axis-aligned to the world.
--
-- Trees are the awkward case: the ray finds the entity -- the crosshair goes
-- green -- and then the streaming module refuses to measure the archetype, so
-- there is nothing to draw a box from. Falling back to a post on the prop's
-- origin still says unmistakably "this one", just without the size, which
-- beats the highlight silently doing nothing.
function Render.box(entity)
  if not entity then return end

  local exists, alive = pcall(DoesEntityExist, entity)
  if not exists or not alive then return end

  local colour = Config.OutlineColour
  local min, max = dimensions(entity)

  -- Measured or not, the prop IS selected and E will copy it. Say so loudly:
  -- a highlight that quietly does nothing is indistinguishable from a
  -- raycast that found nothing, and that confusion cost a lot of time.
  if not min then
    Render.unmeasured = true
    local gotCoords, coords = pcall(GetEntityCoords, entity)
    if gotCoords and coords then
      ring(coords, colour, 2.5)
      marker(coords, colour, 220, 0.8)
    end
    return
  end

  Render.unmeasured = false

  local corners = {
    vector3(min.x, min.y, min.z), vector3(max.x, min.y, min.z),
    vector3(max.x, max.y, min.z), vector3(min.x, max.y, min.z),
    vector3(min.x, min.y, max.z), vector3(max.x, min.y, max.z),
    vector3(max.x, max.y, max.z), vector3(min.x, max.y, max.z),
  }

  local world = {}
  for i = 1, 8 do
    local c = corners[i]
    world[i] = GetOffsetFromEntityInWorldCoords(entity, c.x, c.y, c.z)
  end

  for _, edge in ipairs(EDGES) do
    local a, b = world[edge[1]], world[edge[2]]
    DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, colour.r, colour.g, colour.b, 255)
  end
end

-- The shader glow, where the build has it. Purely cosmetic: the box is what
-- you are meant to read. An outline stays on until something switches it off,
-- so the previous one always goes before the next arrives -- skip that and
-- you leave a trail of lit-up props behind you.
function Render.outline(entity)
  if not drawOutline or outlined == entity then return end

  Render.clear()

  if entity and measurable(entity) then
    if outlineColour then
      pcall(outlineColour, Config.OutlineColour.r, Config.OutlineColour.g, Config.OutlineColour.b, 255)
    end
    pcall(drawOutline, entity, true)
    outlined = entity
  end
end

function Render.clear()
  if drawOutline and outlined then
    pcall(drawOutline, outlined, false)
  end
  outlined = nil
end

-- Asking a map entity for its archetype name throws inside extra-natives. One
-- failure is enough to stop asking for the rest of the session: the name is a
-- convenience, and the box or post already says which prop it is.
local function modelName(entity)
  if not Config.ShowModelNames or archetypeBroken or not archetypeName then return nil end

  local ok, name = pcall(archetypeName, entity)
  if not ok then
    archetypeBroken = true
    return nil
  end

  return (name and name ~= '') and name or nil
end

local lastStatus

-- The readout was DrawText in the lower left, which put it down among the
-- inventory hotbar and the job widgets. It is part of the NUI now, so CSS
-- decides where it sits and it lands under the controls card.
--
-- Pushed only when it CHANGES. This runs every frame, and a NUI message per
-- frame is a real cost for a string that mostly stays the same.
function Render.status(cast, format)
  if not Config.ShowStatus then return end

  local kind, target
  if not cast.hit then
    kind, target = "none", "nothing in range"
  elseif cast.entity then
    kind = "prop"
    target = modelName(cast.entity) or "prop"
    if Render.unmeasured then target = target .. "  (no box)" end
  elseif cast.rejected then
    kind = "near"
    target = ("no entity -- one %.1fm past it"):format(cast.rejected)
  else
    kind, target = "world", "world geometry -- surface only"
  end

  local distance = (cast.hit and cast.coords)
    and #(cast.coords - GetEntityCoords(PlayerPedId())) or nil

  local snap = cast.groundDelta
  if snap and math.abs(snap) <= 0.01 then snap = nil end

  local signature = ("%s|%s|%s|%s|%s"):format(kind, target, tostring(format),
    distance and math.floor(distance * 10) or "-",
    snap and math.floor(snap * 100) or "-")

  if signature == lastStatus then return end
  lastStatus = signature

  SendNUIMessage({
    type = "status",
    kind = kind,
    target = target,
    format = format,
    distance = distance,
    snap = snap,
  })
end

function Render.hideStatus()
  lastStatus = nil
  SendNUIMessage({ type = "status:hide" })
end

-- The reticle. DrawRect takes screen fractions, so a bar that is T wide comes
-- out T*width pixels across but only T*height pixels tall -- scaling the
-- other side by the aspect ratio is what keeps the cross square on any
-- monitor. Colour is the whole point: it says which copy key will work
-- before you press one.
function Render.crosshair(cast)
  if not Config.ShowCrosshair then return end

  local screenW, screenH = GetActiveScreenResolution()
  local aspect = (screenH ~= 0) and (screenW / screenH) or 1.777

  local r, g, b = 255, 255, 255
  if cast.hit and cast.entity then
    r, g, b = Config.OutlineColour.r, Config.OutlineColour.g, Config.OutlineColour.b
  elseif cast.hit then
    r, g, b = 255, 190, 60
  end

  local thickness, length = 0.0011, 0.011
  DrawRect(0.5, 0.5, length, thickness * aspect, r, g, b, 200)
  DrawRect(0.5, 0.5, thickness, length * aspect, r, g, b, 200)
end

-- The highlight half of the H diagnostic. The ray half says whether an entity
-- was found; this says what happened when we tried to draw a box round it,
-- which is the other way a prop appears "undetectable" while being perfectly
-- selectable.
function Render.diagnose(entity)
  local rows = {}

  local function add(label, value)
    rows[#rows + 1] = { label = label, value = value }
  end

  local function attempt(label, fn, ...)
    local ok, a, b = pcall(fn, ...)
    if not ok then
      add(label, ('THREW: %s'):format(tostring(a)))
      return nil
    end
    add(label, tostring(a))
    return a, b
  end

  if not entity then
    add('entity', 'none resolved -- see the probe rows above')
    return rows
  end

  add('entity', tostring(entity))
  attempt('GetEntityType', GetEntityType, entity)

  local model = attempt('GetEntityModel', GetEntityModel, entity)
  if model and model ~= 0 then
    attempt('IsModelValid', IsModelValid, model)

    if not measurable(entity) then
      -- Never call it on a ped merely to fill in a diagnostic line.
      add("GetModelDimensions", "skipped -- peds are never measured")
    else
      local ok, min, max = pcall(GetModelDimensions, model)
      if ok and min and max then
        add("GetModelDimensions", ("%.2f x %.2f x %.2f"):format(max.x - min.x, max.y - min.y, max.z - min.z))
      else
        add("GetModelDimensions", ("THREW: %s"):format(tostring(min)))
      end
    end
  end

  add('SetEntityDrawOutline', tostring(drawOutline ~= nil))
  add('outline colour native', tostring(outlineColour ~= nil))
  add('archetype name usable', tostring(archetypeName ~= nil and not archetypeBroken))

  return rows
end
-- The points you have captured, and -- when they form a zone rather than a
-- plain list -- the shape they make.
--
-- Lines rather than DrawPoly on purpose: a filled polygon is single-sided and
-- vanishes when you fly over it, which is exactly when you most want to see
-- the shape. ox_lib's own debug preview draws the solid walls alongside this.
--
-- `closed` is false for the vector3/vector4 list formats. Those points are not
-- a polygon, and joining them up would imply an order that means nothing.
function Render.zone(points, cursor, thickness, closed, zOffset)
  local count = #points
  local colour = Config.ZoneColour
  local live = Config.ZoneCursorColour
  local top = thickness or 4.0
  local lift = zOffset or 0.0

  -- Everything is drawn at the height it would EXPORT at, not the height it
  -- was captured at, so nudging Z is something you watch happen in the world
  -- rather than a number you read in a box and hope about.
  local at = function(p) return vector3(p.x, p.y, p.z + lift) end

  for i = 1, count do
    local a = at(points[i])

    marker(a, colour, 220, 0.16)

    if closed then
      DrawLine(a.x, a.y, a.z - 1.0, a.x, a.y, a.z + top, colour.r, colour.g, colour.b, 220)

      -- With two points there is one edge, not two: the closing edge only
      -- exists once the shape can actually enclose something.
      if count >= 2 and (i < count or count >= 3) then
        local b = points[i % count + 1]
        DrawLine(a.x, a.y, a.z + 0.05, b.x, b.y, b.z + 0.05, colour.r, colour.g, colour.b, 255)
        DrawLine(a.x, a.y, a.z + top, b.x, b.y, b.z + top, colour.r, colour.g, colour.b, 160)
      end
    else
      -- A short stub instead of a full post: enough to find the point against
      -- dark ground without pretending it is the wall of anything.
      DrawLine(a.x, a.y, a.z, a.x, a.y, a.z + 0.6, colour.r, colour.g, colour.b, 200)
    end
  end

  if not cursor then return end

  -- Drawn lifted like everything else: this is where the next point would
  -- END UP, not where the ray happened to land, and that is the thing worth
  -- previewing while you scroll.
  local aimed = at(cursor)
  marker(aimed, live, 220, 0.18)

  if not closed or count < 1 then return end

  local last = at(points[count])
  DrawLine(last.x, last.y, last.z + 0.05, aimed.x, aimed.y, aimed.z + 0.05,
    live.r, live.g, live.b, 255)

  -- The faint second band shows what the shape would close into, so you can
  -- see a crossing edge before you commit to it.
  if count >= 2 then
    local first = at(points[1])
    DrawLine(aimed.x, aimed.y, aimed.z + 0.05, first.x, first.y, first.z + 0.05,
      live.r, live.g, live.b, 140)
  end
end

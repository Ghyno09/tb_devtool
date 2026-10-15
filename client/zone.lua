-- client/zone.lua
-- The captured point list, and the four things it can be turned into: two
-- zone shapes and two plain coordinate lists. Pure -- no natives, no drawing,
-- no NUI -- which is what makes the awkward parts testable without standing
-- in a field.
--
-- Points are stored exactly as they were captured, each with its own height
-- and heading. Flattening happens when a ZONE snippet is built, never on the
-- way in, so switching format back and forth never quietly destroys the
-- heights you gathered.

Zone = {}

-- Zone formats describe one flat shape extruded upwards. List formats are
-- just coordinates, and each one keeps the height it was taken at.
local ZONE_FORMATS = { oxlib = true, polyzone = true }
local ALL_FORMATS = { 'oxlib', 'polyzone', 'v3', 'v4' }

function Zone.isZone(format)
  return ZONE_FORMATS[format] == true
end

-- A polygon needs three corners. A list of coordinates is useful from one.
function Zone.minPoints(format)
  return Zone.isZone(format) and 3 or 1
end

function Zone.formats()
  return ALL_FORMATS
end

function Zone.new()
  return {
    points = {},
    thickness = Config.ZoneThickness or 4.0,
    name = "zone",
    format = Config.DefaultZoneFormat or "oxlib",
    zOffset = 0.0,
  }
end

function Zone.count(state)
  return #state.points
end

-- The plane a zone sits on. The first point sets it and the snippet flattens
-- the rest onto it; a polygon whose corners sit at different heights is not
-- planar and the zone tests wrong, which you cannot see in game because the
-- outline still looks like a shape.
function Zone.planarZ(state, fallback)
  local first = state.points[1]
  return first and first.z or fallback
end

-- Two points in the same place make a degenerate edge. Easy to do by accident
-- when the freecam drifts a few centimetres between clicks.
--
-- Measured flat for a zone, because two corners above each other are the same
-- corner. Measured in 3D for a list, because stacked coordinates -- one per
-- floor of a building, say -- are exactly the sort of thing you gather.
local function tooClose(state, coords, spacing)
  local flat = Zone.isZone(state.format)

  for i = 1, #state.points do
    local point = state.points[i]
    local dx, dy = point.x - coords.x, point.y - coords.y
    local dz = flat and 0.0 or (point.z - coords.z)

    if math.sqrt(dx * dx + dy * dy + dz * dz) < spacing then return i end
  end

  return nil
end

---@return boolean added, string message
function Zone.add(state, coords, spacing, heading)
  if not coords then return false, 'Nothing under the crosshair.' end

  spacing = spacing or Config.ZoneMinSpacing or 0.25

  local duplicate = tooClose(state, coords, spacing)
  if duplicate then
    return false, ('Too close to point %d.'):format(duplicate)
  end

  state.points[#state.points + 1] = {
    x = coords.x,
    y = coords.y,
    z = coords.z,
    heading = heading or 0.0,
  }

  return true, ('Point %d captured.'):format(#state.points)
end

function Zone.undo(state)
  local last = #state.points
  if last == 0 then return false, 'No points to undo.' end

  state.points[last] = nil
  return true, ('Removed point %d.'):format(last)
end

function Zone.remove(state, index)
  if not state.points[index] then return false, 'No such point.' end

  table.remove(state.points, index)
  return true, ('Removed point %d.'):format(index)
end

-- Order is the polygon: edges join consecutive points, so swapping two is how
-- you fix a zone that crosses over itself. For a plain list it is just the
-- order they come out in.
function Zone.move(state, index, delta)
  local target = index + delta
  if not state.points[index] or not state.points[target] then
    return false, 'Cannot move that point.'
  end

  state.points[index], state.points[target] = state.points[target], state.points[index]
  return true, ('Moved point %d.'):format(index)
end

-- A live height correction applied to every point on the way OUT, never baked
-- into the stored coordinates. Ground snapping puts a point on the collision
-- surface, which on sand sits under the sand you can see; this is the manual
-- adjustment for whatever the automatic one could not know about. Because it
-- is applied at export it lifts points you already placed, and winding it back
-- to zero restores exactly what was captured.
local function clampOffset(value)
  return math.max(-50.0, math.min(50.0, value))
end

function Zone.nudge(state, delta)
  if type(delta) ~= "number" then return false, "Not a number." end

  state.zOffset = clampOffset((state.zOffset or 0.0) + delta)
  return true, ("Z offset %+.2fm."):format(state.zOffset)
end

function Zone.setOffset(state, value)
  if type(value) ~= "number" then return false, "Not a number." end

  state.zOffset = clampOffset(value)
  return true, ("Z offset %+.2fm."):format(state.zOffset)
end

-- The height a point is exported at, as opposed to the height it was captured
-- at. Everything that writes a coordinate goes through here.
function Zone.exportZ(state, point)
  return point.z + (state.zOffset or 0.0)
end

function Zone.clear(state)
  state.points = {}
  return true, 'Cleared.'
end

function Zone.setFormat(state, format)
  for _, allowed in ipairs(ALL_FORMATS) do
    if format == allowed then
      state.format = format
      return true
    end
  end
  return false
end

-- Half the thickness below the first point and half above, so the zone
-- straddles the height you drew it at rather than starting there.
function Zone.bounds(state)
  local z = Zone.planarZ(state, 0.0) + (state.zOffset or 0.0)
  local half = (state.thickness or 4.0) / 2
  return z - half, z + half
end

local function decimals()
  return ('%%.%df'):format(Config.Precision or 2)
end

-- ox_lib takes vector3 points plus a thickness. Flattened to the plane here,
-- not at capture time.
local function oxLibSnippet(state)
  local number = decimals()
  local z = Zone.planarZ(state, 0.0) + (state.zOffset or 0.0)
  local lines = { 'lib.zones.poly({', '  points = {' }

  for _, point in ipairs(state.points) do
    lines[#lines + 1] = ('    vec3(%s, %s, %s),'):format(
      number:format(point.x), number:format(point.y), number:format(z))
  end

  lines[#lines + 1] = '  },'
  lines[#lines + 1] = ('  thickness = %s,'):format(number:format(state.thickness))
  lines[#lines + 1] = '})'

  return table.concat(lines, '\n')
end

-- PolyZone takes flat vector2 points and a separate min/max Z. Kept alongside
-- ox_lib rather than instead of it: plenty of older scripts want this shape.
local function polyZoneSnippet(state)
  local number = decimals()
  local minZ, maxZ = Zone.bounds(state)
  local lines = { 'PolyZone:Create({' }

  for _, point in ipairs(state.points) do
    lines[#lines + 1] = ('  vector2(%s, %s),'):format(
      number:format(point.x), number:format(point.y))
  end

  lines[#lines + 1] = '}, {'
  lines[#lines + 1] = ("  name = '%s',"):format(state.name or 'zone')
  lines[#lines + 1] = ('  minZ = %s,'):format(number:format(minZ))
  lines[#lines + 1] = ('  maxZ = %s,'):format(number:format(maxZ))
  lines[#lines + 1] = '})'

  return table.concat(lines, '\n')
end

-- A bare table literal, so it pastes into whatever field wants a list of
-- coordinates without having to be unwrapped first. Every point keeps the
-- height it was captured at -- these are not a shape.
local function listSnippet(state, withHeading)
  local number = decimals()
  local lines = { '{' }

  for _, point in ipairs(state.points) do
    if withHeading then
      lines[#lines + 1] = ('  vector4(%s, %s, %s, %s),'):format(
        number:format(point.x), number:format(point.y),
        number:format(Zone.exportZ(state, point)), number:format(point.heading or 0.0))
    else
      lines[#lines + 1] = ('  vector3(%s, %s, %s),'):format(
        number:format(point.x), number:format(point.y), number:format(Zone.exportZ(state, point)))
    end
  end

  lines[#lines + 1] = '}'

  return table.concat(lines, '\n')
end

local BUILDERS = {
  oxlib = oxLibSnippet,
  polyzone = polyZoneSnippet,
  v3 = function(state) return listSnippet(state, false) end,
  v4 = function(state) return listSnippet(state, true) end,
}

---@return string? snippet, string? error
function Zone.snippet(state, format)
  format = format or state.format

  local build = BUILDERS[format]
  if not build then
    return nil, ('Unknown format "%s".'):format(tostring(format))
  end

  local needed = Zone.minPoints(format)
  if #state.points < needed then
    return nil, needed == 1
      and 'Capture a point to get started.'
      or ('A zone needs at least %d points.'):format(needed)
  end

  return build(state)
end

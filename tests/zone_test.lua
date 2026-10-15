-- The captured point list and the four things it turns into. All of this is
-- reachable from the NUI panel as well as the keys, so it has to hold up
-- against indices and formats the panel might invent.

local function xyzh(x, y, z, h) return { x = x, y = y, z = z, heading = h } end

local function withFormat(format)
  local state = Zone.new()
  Zone.setFormat(state, format)
  return state
end

---------------------------------------------------------------------------
-- Points are stored as captured
---------------------------------------------------------------------------

-- Flattening happens when a ZONE snippet is built, never on the way in. Store
-- points flattened and switching to vec3 would hand back heights that were
-- silently overwritten -- data destroyed by a UI toggle.
local state = withFormat('oxlib')
Zone.add(state, xyzh(10, 10, 30.5), 0.25, 90)
Zone.add(state, xyzh(20, 10, 42.9), 0.25, 180)

T.near(state.points[1].z, 30.5, 1e-6, "the first point keeps its height")
T.near(state.points[2].z, 42.9, 1e-6, "and so does the second, even in a zone format")
T.near(state.points[2].heading, 180, 1e-6, "the heading you were facing is kept too")

---------------------------------------------------------------------------
-- Duplicate rejection
---------------------------------------------------------------------------

-- In a zone, two corners above each other are the same corner, so the check
-- is flat.
state = withFormat('oxlib')
Zone.add(state, xyzh(5, 5, 30), 0.25)
local added, message = Zone.add(state, xyzh(5, 5, 90), 0.25)
T.eq(added, false, "height does not rescue a duplicate corner in a zone")
T.ok(message:find("1"), "and the message names the point it clashed with")

-- In a list it does: stacked coordinates, one per floor of a building, are
-- exactly the sort of thing you gather.
state = withFormat('v3')
Zone.add(state, xyzh(5, 5, 30), 0.25)
T.eq(Zone.add(state, xyzh(5, 5, 90), 0.25), true, "stacked points are fine in a list")
T.eq(Zone.add(state, xyzh(5, 5, 30.1), 0.25), false, "but a genuinely coincident one is not")

T.eq(Zone.add(state, nil), false, "capturing nothing is refused rather than stored as a nil")

---------------------------------------------------------------------------
-- Undo, remove, reorder
---------------------------------------------------------------------------

state = withFormat('oxlib')
for i = 1, 4 do Zone.add(state, xyzh(i, i, 10)) end

T.eq(Zone.undo(state), true, "undo removes the last point")
T.eq(#state.points, 3, "leaving the rest")

Zone.remove(state, 2)
T.eq(#state.points, 2, "removing by index shortens the list")
T.near(state.points[2].x, 3, 1e-6, "and closes the gap rather than leaving a hole")
T.eq(Zone.remove(state, 99), false, "an index the panel invented is refused")
T.eq(Zone.remove(state, 0), false, "so is a zero index")

Zone.clear(state)
T.eq(Zone.undo(state), false, "undo on an empty list is refused, not an error")

state = withFormat('oxlib')
for i = 1, 3 do Zone.add(state, xyzh(i, i, 10)) end
Zone.move(state, 1, 1)
T.near(state.points[1].x, 2, 1e-6, "moving down swaps with the next point")
T.near(state.points[2].x, 1, 1e-6, "both ways")
T.eq(Zone.move(state, 1, -1), false, "moving the first point up is refused")
T.eq(Zone.move(state, 3, 1), false, "moving the last point down is refused")

---------------------------------------------------------------------------
-- Formats
---------------------------------------------------------------------------

T.eq(#Zone.formats(), 4, "four formats are offered to the panel")
T.eq(Zone.isZone('oxlib'), true, "ox_lib is a zone shape")
T.eq(Zone.isZone('polyzone'), true, "so is PolyZone")
T.eq(Zone.isZone('v3'), false, "a vec3 list is not")
T.eq(Zone.isZone('v4'), false, "nor is a vec4 list")

T.eq(Zone.minPoints('oxlib'), 3, "a polygon needs three corners")
T.eq(Zone.minPoints('v3'), 1, "a list is useful from one point")

state = Zone.new()
T.eq(Zone.setFormat(state, 'v4'), true, "a known format is accepted")
T.eq(state.format, 'v4', "and stored")
T.eq(Zone.setFormat(state, 'nonsense'), false, "an invented one is refused")
T.eq(state.format, 'v4', "and leaves the format alone")
T.eq(Zone.setFormat(state, nil), false, "so is nothing at all")

---------------------------------------------------------------------------
-- Snippets
---------------------------------------------------------------------------

state = withFormat('oxlib')
local snippet, err = Zone.snippet(state)
T.eq(snippet, nil, "no zone from an empty list")
T.ok(err:find("3"), "and it says how many are needed")

-- Deliberately at three different heights, to prove the zone snippet
-- flattens and the list snippets do not.
Zone.add(state, xyzh(215.4, -810.2, 30.7), 0.25, 90.0)
Zone.add(state, xyzh(219.1, -804.6, 44.9), 0.25, 12.5)
T.eq(Zone.snippet(state), nil, "two points is still not a polygon")

Zone.add(state, xyzh(224.8, -806.9, 12.1), 0.25, 270.0)
state.thickness = 4.0

snippet = Zone.snippet(state)
T.ok(snippet:find("lib.zones.poly", 1, true), "ox_lib snippet calls lib.zones.poly")
T.ok(snippet:find("vec3(215.40, -810.20, 30.70)", 1, true), "the first point sets the plane")
T.ok(snippet:find("vec3(219.10, -804.60, 30.70)", 1, true), "the second is flattened onto it")
T.ok(snippet:find("vec3(224.80, -806.90, 30.70)", 1, true), "and so is the third")
T.eq(snippet:find("44.90", 1, true), nil, "no original height survives into a zone snippet")
T.ok(snippet:find("thickness = 4.00", 1, true), "the thickness is carried through")
T.eq(select(2, snippet:gsub("vec3%(", "")), 3, "one vec3 per point, no more")

snippet = Zone.snippet(state, 'polyzone')
T.ok(snippet:find("PolyZone:Create", 1, true), "PolyZone snippet calls PolyZone:Create")
T.ok(snippet:find("vector2(215.40, -810.20)", 1, true), "with vector2 points")
T.eq(snippet:find("vec3", 1, true), nil, "and no vec3 anywhere in it")
T.ok(snippet:find("minZ = 28.70", 1, true), "minZ is half the thickness below the plane")
T.ok(snippet:find("maxZ = 32.70", 1, true), "maxZ is half above it")

-- The list formats keep every height exactly as captured. This is the whole
-- point of them.
snippet = Zone.snippet(state, 'v3')
T.ok(snippet:find("vector3(215.40, -810.20, 30.70)", 1, true), "vec3 list keeps the first height")
T.ok(snippet:find("vector3(219.10, -804.60, 44.90)", 1, true), "and the second, unflattened")
T.ok(snippet:find("vector3(224.80, -806.90, 12.10)", 1, true), "and the third")
T.eq(snippet:sub(1, 1), "{", "it is a bare table, ready to paste into a field")
T.eq(snippet:find("thickness", 1, true), nil, "a list has no thickness")

snippet = Zone.snippet(state, 'v4')
T.ok(snippet:find("vector4(215.40, -810.20, 30.70, 90.00)", 1, true), "vec4 list carries the heading")
T.ok(snippet:find("vector4(219.10, -804.60, 44.90, 12.50)", 1, true), "per point")
T.eq(select(2, snippet:gsub("vector4%(", "")), 3, "one vector4 per point")

-- One point is a valid list and an invalid zone. Both answers matter.
state = withFormat('v4')
Zone.add(state, xyzh(1, 2, 3), 0.25, 45.0)
T.ok(Zone.snippet(state) ~= nil, "a single point is a usable list")
T.eq(Zone.snippet(state, 'oxlib'), nil, "but not a usable zone")

snippet, err = Zone.snippet(state, 'nonsense')
T.eq(snippet, nil, "an unknown format yields no snippet")
T.ok(err:find("nonsense", 1, true), "and names what it did not recognise")

local minZ, maxZ = Zone.bounds(state)
T.near(maxZ - minZ, state.thickness, 1e-6, "the bounds span exactly the thickness")
state.thickness = 10.0
minZ, maxZ = Zone.bounds(state)
T.near(minZ, -2.0, 1e-6, "a thicker zone reaches further below the plane")

---------------------------------------------------------------------------
-- Render.zone: the live outline
---------------------------------------------------------------------------

local function pts(...)
  local out = {}
  for _, p in ipairs({ ... }) do out[#out + 1] = { x = p[1], y = p[2], z = p[3] } end
  return out
end

Stub.reset()
Render.zone(pts(), nil, 4.0, true)
T.eq(#Stub.lines, 0, "an empty zone draws nothing")
T.eq(#Stub.markers, 0, "and no markers")

Stub.reset()
Render.zone(pts({ 0, 0, 10 }), { x = 5, y = 0, z = 10 }, 4.0, true)
T.eq(#Stub.lines, 2, "one point gives a post and a rubber band")
T.eq(#Stub.markers, 2, "with a marker on the point and on the crosshair")

-- Two points make ONE edge, not two. Drawing the closing edge here would
-- retrace the same line and make a two-point zone look finished.
Stub.reset()
Render.zone(pts({ 0, 0, 10 }, { 5, 0, 10 }), { x = 5, y = 5, z = 10 }, 4.0, true)
T.eq(#Stub.lines, 6, "two points: 2 posts + 1 edge pair + 2 rubber bands")

Stub.reset()
Render.zone(pts({ 0, 0, 10 }, { 5, 0, 10 }, { 5, 5, 10 }), nil, 4.0, true)
T.eq(#Stub.lines, 9, "three points: 3 posts + 3 edge pairs, no cursor")

Stub.reset()
Render.zone(pts({ 0, 0, 10 }, { 5, 0, 10 }, { 5, 5, 10 }), { x = 0, y = 5, z = 10 }, 4.0, true)
T.eq(#Stub.lines, 11, "and 2 more lines once there is a crosshair to band to")

-- The post has to span the zone it represents, or the thickness you typed
-- into the panel is invisible until you paste the snippet.
Stub.reset()
Render.zone(pts({ 0, 0, 10 }), nil, 6.0, true)
T.near(Stub.lines[1].a.z, 9.0, 1e-6, "the post starts a metre below the plane")
T.near(Stub.lines[1].b.z, 16.0, 1e-6, "and reaches the full thickness above it")

-- A coordinate list is not a polygon. Joining the points up would imply an
-- order that means nothing, and closing the loop would imply a shape.
Stub.reset()
Render.zone(pts({ 0, 0, 10 }, { 5, 0, 20 }, { 5, 5, 30 }), { x = 9, y = 9, z = 9 }, 4.0, false)
T.eq(#Stub.lines, 3, "a list draws one stub per point and no edges")
T.eq(#Stub.markers, 4, "but still marks every point and the crosshair")
T.near(Stub.lines[1].b.z - Stub.lines[1].a.z, 0.6, 1e-6, "the stub is short, not a full wall")
T.near(Stub.lines[2].a.z, 20.0, 1e-6, "and each stub sits at its own point's height")

---------------------------------------------------------------------------
-- Z offset
---------------------------------------------------------------------------
-- Applied on the way OUT, never baked into the stored coordinates. That is
-- what lets it lift points you already placed, and what lets winding it back
-- to zero restore exactly what was captured.

state = withFormat('v3')
Zone.add(state, xyzh(1, 2, 10.00), 0.25, 0)
Zone.add(state, xyzh(3, 4, 12.50), 0.25, 0)

T.near(state.zOffset, 0.0, 1e-9, "a new zone starts unshifted")

Zone.nudge(state, 0.35)
T.near(state.zOffset, 0.35, 1e-9, "nudging raises the offset")
T.near(Zone.exportZ(state, state.points[1]), 10.35, 1e-9, "and lifts the export height")
T.near(state.points[1].z, 10.00, 1e-9, "while the captured coordinate is untouched")
T.near(Zone.exportZ(state, state.points[2]), 12.85, 1e-9, "every point moves, not just the first")

Zone.nudge(state, -0.35)
T.near(state.zOffset, 0.0, 1e-9, "winding it back reaches exactly zero")
T.near(Zone.exportZ(state, state.points[1]), 10.00, 1e-9, "and restores the captured height exactly")

-- A stuck scroll wheel must not send points to orbit.
Zone.nudge(state, 900)
T.near(state.zOffset, 50.0, 1e-9, "the offset clamps upwards")
Zone.nudge(state, -900)
T.near(state.zOffset, -50.0, 1e-9, "and downwards")

T.eq(Zone.setOffset(state, 2.5), true, "the panel can set it directly")
T.near(state.zOffset, 2.5, 1e-9, "to an exact value")
T.eq(Zone.setOffset(state, 'nonsense'), false, "but not to something that is not a number")
T.eq(Zone.nudge(state, nil), false, "and nudging by nothing is refused")
T.near(state.zOffset, 2.5, 1e-9, "with the offset left alone")

-- Every output has to agree with the offset, or the panel and the snippet
-- would disagree about where the points are.
Zone.setOffset(state, 1.0)
local out = Zone.snippet(state, 'v3')
T.ok(out:find("vector3(1.00, 2.00, 11.00)", 1, true), "vec3 exports at the offset height")
T.ok(out:find("vector3(3.00, 4.00, 13.50)", 1, true), "for every point")

out = Zone.snippet(state, 'v4')
T.ok(out:find("11.00", 1, true), "vec4 does too")

state = withFormat('oxlib')
Zone.add(state, xyzh(1, 1, 30.0), 0.25, 0)
Zone.add(state, xyzh(2, 2, 30.0), 0.25, 0)
Zone.add(state, xyzh(3, 3, 30.0), 0.25, 0)
state.thickness = 4.0
Zone.setOffset(state, 0.5)

out = Zone.snippet(state, 'oxlib')
T.ok(out:find("vec3(1.00, 1.00, 30.50)", 1, true), "the zone plane moves with the offset")
T.eq(out:find("30.00", 1, true), nil, "and the unshifted height does not appear")

out = Zone.snippet(state, 'polyzone')
T.ok(out:find("minZ = 28.50", 1, true), "so do the PolyZone bounds")
T.ok(out:find("maxZ = 32.50", 1, true), "both of them")

local lowZ, highZ = Zone.bounds(state)
T.near(highZ - lowZ, 4.0, 1e-9, "the offset shifts the bounds without resizing them")

-- The world drawing has to show the export height, or raising Z would be a
-- number that changes with nothing visibly moving.
Stub.reset()
Render.zone(pts({ 0, 0, 10 }), nil, 4.0, true, 2.0)
T.near(Stub.markers[1].z, 12.0, 1e-6, "the point marker is drawn lifted")
T.near(Stub.lines[1].a.z, 11.0, 1e-6, "and so is its post")

Stub.reset()
Render.zone(pts({ 0, 0, 10 }), nil, 4.0, true, 0.0)
T.near(Stub.markers[1].z, 10.0, 1e-6, "with no offset it sits where it was captured")

Stub.reset()
Render.zone(pts({ 0, 0, 10 }, { 5, 0, 10 }, { 5, 5, 10 }), nil, 4.0, true, 1.5)
for i, line in ipairs(Stub.lines) do
  T.ok(line.a.z >= 10.5 - 1e-6, ("edge %d is drawn at or above the lifted plane"):format(i))
end

-- The crosshair marker previews where the NEXT point would end up, so it is
-- lifted like the placed ones. Without this, scrolling Z before your first
-- point moves nothing visible at all and looks broken.
Stub.reset()
Render.zone(pts(), { x = 3, y = 4, z = 10 }, 4.0, true, 1.25)
T.eq(#Stub.markers, 1, "the crosshair is marked with no points placed")
T.near(Stub.markers[1].z, 11.25, 1e-6, "at the height the point would export to")

Stub.reset()
Render.zone(pts({ 0, 0, 10 }), { x = 3, y = 4, z = 10 }, 4.0, true, 2.0)
T.near(Stub.markers[2].z, 12.0, 1e-6, "the crosshair stays lifted alongside placed points")
local band = Stub.lines[#Stub.lines]
T.near(band.b.z, 12.05, 1e-6, "and the rubber band reaches it there, not at the raw hit")

Stub.reset()
Render.zone(pts(), { x = 3, y = 4, z = 10 }, 4.0, false, 0.75)
T.near(Stub.markers[1].z, 10.75, 1e-6, "list mode lifts the crosshair too")

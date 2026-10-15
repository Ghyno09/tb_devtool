-- Two things here. The forward vector, which can be wrong without looking
-- wrong -- a beam a few degrees off still draws a convincing line to the
-- wrong prop. And Ray.choose, which is the rule that decides whether you are
-- allowed to select a tree.

-- Unit length: anything else silently scales MaxDistance, so the ray would
-- reach a different number of metres depending on where you looked.
for _, aim in ipairs({ { 0, 0 }, { 90, 0 }, { 180, 45 }, { 270, -30 }, { 37, 12 } }) do
  Stub.aim(aim[1], aim[2])
  T.near(#Ray.direction(), 1.0, 1e-4, ("unit length at yaw %d pitch %d"):format(aim[1], aim[2]))
end

-- GTA headings run anticlockwise from north: 0 is +y, 90 is west, 180 south.
Stub.aim(0, 0)
local d = Ray.direction()
T.near(d.x, 0.0, 1e-3, "heading 0 faces north on x")
T.near(d.y, 1.0, 1e-3, "heading 0 faces north on y")

Stub.aim(90, 0)
d = Ray.direction()
T.near(d.x, -1.0, 1e-3, "heading 90 faces west on x")
T.near(d.y, 0.0, 1e-3, "heading 90 faces west on y")

Stub.aim(180, 0)
d = Ray.direction()
T.near(d.x, 0.0, 1e-3, "heading 180 faces south on x")
T.near(d.y, -1.0, 1e-3, "heading 180 faces south on y")

Stub.aim(0, 30)
d = Ray.direction()
T.near(d.z, math.sin(math.rad(30)), 1e-3, "pitch 30 lifts z by sin(30)")
T.near(d.y, math.cos(math.rad(30)), 1e-3, "pitch 30 shortens y to cos(30)")

Stub.aim(0, -30)
T.ok(Ray.direction().z < 0, "negative pitch aims downwards")

---------------------------------------------------------------------------
-- Ray.choose: which of the two passes to believe.
---------------------------------------------------------------------------

local function pass(hit, entity, distance)
  return { hit = hit, entity = entity, distance = distance or math.huge, coords = vector3(0, 0, 0) }
end

-- The easy case: the map-inclusive pass already found an entity.
local world = pass(true, 77, 5.0)
T.eq(Ray.choose(world, pass(true, 88, 4.0), 0.25), world, "first pass wins when it has an entity")

-- THE TREE CASE. Aiming at a trunk, the map-inclusive pass stops on the map
-- bound and reports no entity; the entity-only pass goes through it and finds
-- the tree at essentially the same spot. The tree must win, or trees can
-- never be selected -- which is exactly the bug this pins down.
local trunk = pass(true, nil, 5.00)
local tree = pass(true, 42, 5.10)
T.eq(Ray.choose(trunk, tree, 0.25), tree, "entity just behind a map bound wins")

-- Same again but outside the tolerance: this is a prop on the far side of a
-- wall, and the wall has to keep winning or you would select through walls.
local wall = pass(true, nil, 5.0)
local behind = pass(true, 42, 25.0)
T.eq(Ray.choose(wall, behind, 0.25), wall, "an entity beyond the tolerance does not win")

-- Tolerance is a boundary, so check both sides of it rather than the middle.
T.eq(Ray.choose(pass(true, nil, 5.0), pass(true, 42, 5.24), 0.25).entity, 42, "just inside the tolerance wins")
T.eq(Ray.choose(pass(true, nil, 5.0), pass(true, 42, 5.26), 0.25).entity, nil, "just outside the tolerance loses")

-- Nothing stopped the first pass at all, so there is no map bound to respect.
local nothing = pass(false, nil, math.huge)
local found = pass(true, 42, 60.0)
T.eq(Ray.choose(nothing, found, 0.25), found, "a miss on the first pass yields to any entity")

-- The second pass found nothing worth having: keep the honest answer.
T.eq(Ray.choose(world, pass(false, nil), 0.25).distance, 5.0, "a missed second pass changes nothing")
T.eq(Ray.choose(trunk, pass(true, nil, 5.0), 0.25), trunk, "a second pass with no entity changes nothing")
T.eq(Ray.choose(trunk, nil, 0.25), trunk, "a missing second pass changes nothing")

-- Open sky: both passes miss, and the caller still needs a table back.
local sky = pass(false, nil)
T.eq(Ray.choose(sky, pass(false, nil), 0.25), sky, "both passes missing still returns the first")

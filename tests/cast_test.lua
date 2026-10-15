-- Ray.cast escalates through up to three probes to resolve a prop the map
-- bound is hiding. This is the part that decides whether a given tree can be
-- selected at all, so every rung of the ladder gets a test.

local WORLD = Config.RayFlags             -- 511, everything, stops honestly
local ENTITY = Config.RayFlagsEntityOnly  -- 510, everything except the map

Stub.aim(0, 0)

-- The easy case: the map-inclusive pass found the entity itself. No further
-- probing, and nothing rejected to report.
Stub.reset()
Stub.probe(WORLD, true, 42, 5.0)
local cast = Ray.cast()
T.eq(cast.entity, 42, "first pass entity is used directly")
T.eq(cast.rejected, nil, "a clean first-pass hit rejects nothing")
T.near(cast.distance, 5.0, 1e-3, "distance comes from the first pass")

-- THE TRUNK CASE. Aiming at a trunk, the map-inclusive pass stops on the map
-- bound and reports no entity; the map-excluded pass goes through it and
-- finds the tree just behind. The tree has to win, or that trunk can never be
-- selected however carefully you aim at it.
Stub.reset()
Stub.probe(WORLD, true, 0, 5.0)
Stub.probe(ENTITY, true, 42, 5.8)
cast = Ray.cast()
T.eq(cast.entity, 42, "an entity just behind a map bound is resolved")

-- Same shape, but the entity is across the orchard. The surface has to keep
-- winning or you would select straight through walls.
Stub.reset()
Stub.probe(WORLD, true, 0, 5.0)
Stub.probe(ENTITY, true, 42, 30.0)
cast = Ray.cast()
T.eq(cast.entity, nil, "an entity far beyond the surface is not resolved")
T.near(cast.rejected, 25.0, 1e-3, "how far past it was gets reported")

-- The swept sphere is the last resort: a hairline probe can pass between two
-- bounds that nearly touch, and a fat one catches what it missed.
Stub.reset()
Stub.probe(WORLD, true, 0, 5.0)
Stub.probe(ENTITY, false, 0, nil)
Stub.sphere = { hit = true, entity = 99, distance = 5.4 }
cast = Ray.cast()
T.eq(cast.entity, 99, "the swept sphere rescues what the thin ray missed")

-- ...but it obeys the same tolerance. A sphere hit across the field loses.
Stub.reset()
Stub.probe(WORLD, true, 0, 5.0)
Stub.probe(ENTITY, false, 0, nil)
Stub.sphere = { hit = true, entity = 99, distance = 40.0 }
cast = Ray.cast()
T.eq(cast.entity, nil, "a distant swept-sphere hit is still rejected")
T.near(cast.rejected, 35.0, 1e-3, "the swept sphere reports its distance too")

-- Genuinely bare terrain: nothing anywhere has an entity, and the readout
-- must not claim something was nearly found.
Stub.reset()
Stub.probe(WORLD, true, 0, 5.0)
Stub.probe(ENTITY, false, 0, nil)
cast = Ray.cast()
T.eq(cast.entity, nil, "bare terrain resolves to no entity")
T.eq(cast.rejected, nil, "bare terrain rejects nothing")
T.ok(cast.hit, "bare terrain still reports a surface to copy")

-- Open sky. Nothing stopped anything, so there is no surface and no entity,
-- but the caller still needs a table rather than a nil.
Stub.reset()
Stub.probe(WORLD, false, 0, nil)
Stub.probe(ENTITY, false, 0, nil)
cast = Ray.cast()
T.eq(cast.hit, false, "open sky is not a hit")
T.eq(cast.entity, nil, "open sky has no entity")
T.ok(cast.limit ~= nil, "open sky still carries the far end for the beam")

-- Nothing stopped the first pass but something is out there: no map bound
-- means nothing to respect, so the entity wins at any distance.
Stub.reset()
Stub.probe(WORLD, false, 0, nil)
Stub.probe(ENTITY, true, 42, 60.0)
cast = Ray.cast()
T.eq(cast.entity, 42, "with no surface in the way, distance does not matter")

-- The nearer of two rejected candidates is the one worth reporting, since it
-- is the one that would come into range first if the tolerance were raised.
Stub.reset()
Stub.probe(WORLD, true, 0, 5.0)
Stub.probe(ENTITY, true, 42, 30.0)
Stub.sphere = { hit = true, entity = 99, distance = 12.0 }
cast = Ray.cast()
T.near(cast.rejected, 7.0, 1e-3, "the nearest rejected candidate is reported")

-- A build without the swept-sphere native must degrade to two passes rather
-- than erroring, so the picker keeps working on whatever this server runs.
Stub.reset()
Stub.probe(WORLD, true, 0, 5.0)
Stub.probe(ENTITY, true, 42, 5.5)
local saved = StartShapeTestSweptSphere
StartShapeTestSweptSphere = nil
local ok, resolved = pcall(Ray.cast)
StartShapeTestSweptSphere = saved
T.ok(ok, "a missing swept-sphere native does not error")
T.eq(ok and resolved.entity, 42, "two passes still resolve without the third")

-- And one that throws is no worse than one that is absent.
Stub.reset()
Stub.probe(WORLD, true, 0, 5.0)
Stub.probe(ENTITY, false, 0, nil)
Stub.throws.StartShapeTestSweptSphere = true
ok = pcall(Ray.cast)
T.ok(ok, "a throwing swept-sphere native does not propagate")

---------------------------------------------------------------------------
-- Ray.diagnose: the H key. This is what has to be trustworthy when a prop
-- still will not select, so it reports raw entityHit values UNFILTERED --
-- a nonzero raw with a nil resolved means DoesEntityExist rejected it, which
-- is a completely different problem from no probe seeing anything.
---------------------------------------------------------------------------

Stub.reset()
Stub.probe(WORLD, true, 0, 5.0)
Stub.probe(ENTITY, true, 42, 30.0)
Stub.sphere = { hit = true, entity = 0, distance = 5.1 }

local rows = Ray.diagnose()
T.eq(#rows, 4, "three probes plus the ground-snap row")
T.ok(rows[4].snap, "the fourth row is the ground comparison")
T.near(rows[4].raw, 0.0, 1e-6, "reporting the z the probe landed at")
T.ok(rows[4].z ~= nil, "alongside the collision ground z, so the two can be compared")

T.eq(rows[1].raw, 0, "a map-bound hit reports entityHit 0 rather than hiding it")
T.ok(rows[1].hit, "the first row still records that something was hit")
T.near(rows[1].distance, 5.0, 1e-3, "the first row records where")

T.eq(rows[2].raw, 42, "a rejected entity is still reported raw")
T.eq(rows[2].resolved, 42, "and resolved, so the tolerance is visibly the reason")
T.near(rows[2].distance, 30.0, 1e-3, "with the distance that got it rejected")

-- Diagnosing must never be what breaks the session.
Stub.reset()
Stub.probe(WORLD, true, 0, 5.0)
local savedSweep = StartShapeTestSweptSphere
StartShapeTestSweptSphere = nil
local diagnosed, out = pcall(Ray.diagnose)
StartShapeTestSweptSphere = savedSweep
T.ok(diagnosed, "diagnose survives a missing swept-sphere native")
T.ok(diagnosed and out[3].missing, "and says so rather than dropping the row")


---------------------------------------------------------------------------
-- Ground snapping
---------------------------------------------------------------------------
-- GTA draws terrain from one mesh and collides it with another. On sand they
-- disagree by tens of centimetres, so a raw probe hands back a z that reads as
-- under the floor. These pin down when we correct it and, more importantly,
-- when we must not.

local function bareGround(distance)
  Stub.reset()
  Stub.probe(WORLD, true, 0, distance or 5.0)
  Stub.probe(ENTITY, false, 0, nil)
end

bareGround()
Stub.groundZ = -0.35
cast = Ray.cast()
T.near(cast.coords.z, -0.35, 1e-6, "bare ground snaps to the collision height")
T.near(cast.rawCoords.z, 0.0, 1e-6, "and the probe's own answer is kept")
T.near(cast.groundDelta, -0.35, 1e-6, "with the correction reported")

-- A point ON a prop must never be dragged to the dirt below it: aiming at a
-- table top and getting the floor would be worse than no snapping at all.
Stub.reset()
Stub.probe(WORLD, true, 42, 5.0)
Stub.groundZ = -8.0
cast = Ray.cast()
T.eq(cast.entity, 42, "the prop is still resolved")
T.near(cast.coords.z, 0.0, 1e-6, "and its hit point is left exactly where it was")
T.eq(cast.groundDelta, nil, "with no correction claimed")

-- Standing on a pier, the ground is a long way down. Beyond SnapMaxDrop the
-- raw hit is kept, because moving the point that far is not a correction.
bareGround()
Stub.groundZ = -14.0
cast = Ray.cast()
T.near(cast.coords.z, 0.0, 1e-6, "a drop beyond the limit is refused")
T.near(cast.groundDelta, -14.0, 1e-6, "but still reported, so the readout can explain itself")

-- Right at the boundary, both sides.
bareGround()
Stub.groundZ = -(Config.SnapMaxDrop - 0.01)
T.ok(Ray.cast().coords.z < -0.5, "just inside the limit snaps")
bareGround()
Stub.groundZ = -(Config.SnapMaxDrop + 0.01)
T.near(Ray.cast().coords.z, 0.0, 1e-6, "just outside it does not")

-- Terrain the collision does not know about must not move the point to zero.
bareGround()
Stub.groundFound = false
cast = Ray.cast()
T.near(cast.coords.z, 0.0, 1e-6, "an unknown ground height leaves the point alone")
T.eq(cast.groundDelta, nil, "and claims no correction")

-- The switch has to actually switch it off.
local wasEnabled = Config.SnapToGround
Config.SnapToGround = false
bareGround()
Stub.groundZ = -0.35
T.near(Ray.cast().coords.z, 0.0, 1e-6, "SnapToGround = false disables it entirely")
Config.SnapToGround = wasEnabled

-- A build without the native, and one where it throws, both degrade quietly.
bareGround()
Stub.groundZ = -0.35
local savedGround = GetGroundZFor_3dCoord
GetGroundZFor_3dCoord = nil
local snapOk, snapped = pcall(Ray.cast)
GetGroundZFor_3dCoord = savedGround
T.ok(snapOk, "a missing ground native does not error")
T.near(snapOk and snapped.coords.z or -1, 0.0, 1e-6, "it just does not snap")

bareGround()
Stub.throws.GetGroundZFor_3dCoord = true
T.ok(pcall(Ray.cast), "a throwing ground native does not propagate")

-- Nothing was hit, so there is nothing to snap and nothing to report.
Stub.reset()
Stub.probe(WORLD, false, 0, nil)
Stub.probe(ENTITY, false, 0, nil)
cast = Ray.cast()
T.eq(cast.rawCoords, nil, "a miss has no raw coords")
T.eq(cast.groundDelta, nil, "and no correction")

-- River is out of both flag sets: on a beach the ray would otherwise stop on
-- the water surface rather than the sand under it.
T.eq(Config.RayFlags & 128, 0, "the main pass excludes RIVER")
T.eq(Config.RayFlagsEntityOnly & 128, 0, "so does the entity-only pass")

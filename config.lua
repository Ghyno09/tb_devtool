Config = {}

-- Chat command that toggles the picker. Gated on the server, not here.
Config.Command = 'devtool'

-- Who may run it. A LIST: any one match passes. Servers disagree on which
-- spelling their permissions.cfg grants -- stock Qbox grants the OBJECT
-- "admin" and not "group.admin" -- so naming one and being wrong makes the
-- command vanish with no error. Do not name one.
Config.AdminAce = { 'admin', 'group.admin' }

-- Title on every toast this resource sends.
Config.NotifyTitle = 'Dev Tool'

-- How far the ray reaches, in metres. Past this the beam stops and there is
-- nothing to copy.
Config.MaxDistance = 100.0

-- The laser itself. The server accent.
Config.BeamColour = { r = 238, g = 28, b = 62 }

-- The box drawn around whatever the beam landed on. Deliberately a different
-- colour from the beam: the beam says where you are pointing, the box says
-- what you would actually copy, and confusing the two is the whole problem.
Config.OutlineColour = { r = 60, g = 255, b = 90 }

-- DrawLine is one pixel wide however close you stand to it, which outdoors at
-- night reads as nothing at all. This many passes, nudged around the line's
-- own axis, is the cheapest way to get something you can actually follow.
-- 1 draws a single hairline.
Config.BeamThickness = 5

-- Small readout in the corner: what is under the cursor and how far off it
-- is. Also the quickest way to tell the picker is running at all.
Config.ShowStatus = true

-- Reticle at dead centre. The beam leaves the ped's hand, not the camera, so
-- close up the line sits off to one side of where it actually lands -- the
-- reticle is the honest answer to "what am I about to copy". It turns green
-- over a prop and amber over bare map geometry.
Config.ShowCrosshair = false


-- Output format the picker opens in: 'vector3' or 'vector4'. X toggles it
-- in game; this only decides where it starts.
Config.DefaultFormat = 'vector4'

-- Decimal places in the copied string.
Config.Precision = 2

-- Ped bone the beam leaves from. 24818 = SKEL_R_Hand.
Config.BeamBone = 24818

-- Controls, as FiveM control indices -- not key codes. Every control listed
-- for an action does that action, so LMB and E are interchangeable.
Config.Keys = {
  copyEntity   = { 24, 38 },  -- LMB, E    the prop's own coords
  copySurface  = { 25, 44 },  -- RMB, Q    the exact point the beam landed on
  toggleFormat = { 73 },      -- X         vector3 <-> vector4
  diagnose     = { 74 },      -- H         dump every probe to F8
  exit         = { 177 },     -- BACKSPACE
}

-- What the ray is allowed to hit, summed. From ox_lib's own list:
--   1 mover (the map)  2 vehicle  4 ped  8 ragdoll  16 object
--   32 pickup  64 glass  128 river  256 foliage  511 everything
-- Everything EXCEPT ped (4) and ragdoll (8). Note the 256: TREES ARE FOLIAGE,
-- and a map+objects ray (1+16) stops dead on a trunk reporting no entity at
-- all, which reads as "trees cannot be highlighted" when really they were
-- never being asked for.
--
-- River (128) is out too: on a beach the ray otherwise stops on the water
-- surface rather than the sand beneath it.
--
-- Peds are left out on purpose. This is a prop picker, and handing a ped
-- model to GetModelDimensions does not throw something catchable -- it takes
-- the game down. The ray passes straight through NPCs instead.
Config.RayFlags = 511 - 4 - 8 - 128

-- Second pass, used only when the first reports no entity. Leaving 1 (the
-- map) out lets the ray through a bound that answers first and answers with
-- nothing. ox_target uses 2+8+16 here, but it is not looking for trees: 256
-- (foliage) has to be in the list or a trunk hit can never resolve to the
-- tree behind it, which is why some trees highlighted and some did not.
Config.RayFlagsEntityOnly = 511 - 1 - 4 - 8 - 128

-- How much nearer the second pass has to be before it wins, in metres. The
-- two bounds on the same prop sit almost on top of each other, so it needs
-- slack; too much and a prop behind a wall would beat the wall.
Config.EntityPassTolerance = 1.5


-- Radius of the third pass, a swept sphere instead of a hairline. A thin ray
-- can slip between two bounds that nearly touch, which leaves a prop
-- unselectable however carefully you aim; a fat one catches those. Set to 0
-- to skip the third pass.
Config.SphereRadius = 0.35

---------------------------------------------------------------------------
-- Zone builder (/devzone)
---------------------------------------------------------------------------

-- Chat command that starts the zone builder. Same ace as the picker.
Config.ZoneCommand = 'devzone'

-- Default extrusion height for a new zone, in metres. ox_lib takes this as
-- `thickness`; PolyZone gets it as minZ/maxZ either side of the first point.
Config.ZoneThickness = 4.0

-- Two points closer together than this (measured flat, ignoring height) are
-- treated as the same point and the second is refused. Easy to place by
-- accident when the freecam drifts a few centimetres between clicks.
Config.ZoneMinSpacing = 0.25

-- Colours for the zone builder. Placed points and the finished edges in one
-- colour, the live rubber band to the crosshair in another, so the edge you
-- have not committed to yet is obvious.
Config.ZoneColour = { r = 238, g = 28, b = 62 }
Config.ZoneCursorColour = { r = 255, g = 176, b = 64 }

-- Freecam movement, in metres per second.
-- Mouse look sensitivity for the freecam. Degrees per unit of mouse travel.
Config.FreecamSensitivity = 5.0

Config.FreecamSpeed = 8.0
Config.FreecamFastSpeed = 26.0
Config.FreecamSlowSpeed = 2.0

-- Zone builder controls.
Config.ZoneKeys = {
  addPoint  = { 24, 38 },   -- LMB, E     drop a point under the crosshair
  undoPoint = { 25, 44 },   -- RMB, Q     take the last one back
  raiseZ    = { 241 },      -- SCROLL UP   lift every point (hold SHIFT for a coarse step)
  lowerZ    = { 242 },      -- SCROLL DOWN drop every point
  panel     = { 47 },       -- G          hand the mouse to the panel and back
  confirm   = { 191 },      -- ENTER      copy the snippet
  exit      = { 177 },      -- BACKSPACE
}

-- Live ox_lib zone preview once there are three points: the real walled
-- volume, drawn by ox_lib itself, rather than the wireframe alone. The
-- wireframe shows the shape you are drawing; this shows the zone you would
-- actually get, walls and all.
Config.ZonePreview = true

-- Which output the builder opens on: 'oxlib', 'polyzone', 'v3' or 'v4'.
-- The first two are zone shapes; v3 and v4 are plain coordinate lists where
-- every point keeps its own height, and v4 also keeps the heading you were
-- facing when you captured it.
Config.DefaultZoneFormat = 'oxlib'

-- Snap a captured ground point to the collision surface.
--
-- GTA's rendered terrain and its collision mesh are not the same surface. On
-- sand especially they differ by tens of centimetres -- which is why a ped
-- looks half-buried standing on a beach, and why a raycast against the
-- collision hands back a z that looks like it is under the floor.
-- GetGroundZFor_3dCoord returns the height a ped's feet actually rest at,
-- which is the number you want for placing anything.
Config.SnapToGround = true

-- How large a correction to accept, in metres. Only bare ground is snapped --
-- never a point on a prop -- but terrain under a bridge or a pier would still
-- be a long way down, and dragging the point there would be worse than
-- leaving it. Beyond this the raw hit is kept.
Config.SnapMaxDrop = 1.0

-- How far one scroll notch moves the export height, in metres, and the coarse
-- step when SHIFT is held. Ground snapping puts points on the collision
-- surface; this is the manual correction on top of it, applied on the way out
-- so it lifts points you already placed and winds back to exactly what was
-- captured.
Config.ZoneZStep = 0.05
Config.ZoneZFastStep = 0.5

-- Ask props for their model name to show in the readout.
--
-- Off by default: GetEntityArchetypeName throws inside extra-natives on map
-- entities on this build. The throw is caught and never asked again, but
-- FiveM logs every native exception regardless, so leaving this on buys a
-- console error for a label. The box and the coordinates already identify the
-- prop; turn it on only if you specifically want names.
Config.ShowModelNames = false

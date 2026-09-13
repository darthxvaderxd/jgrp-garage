--[[
    jgrp-garage

    A parking lot is two things: the BOUNDS that mark where the lot is, and an
    ARRAY OF SPOTS inside it where cars actually sit.

      * Sit in a spot in your car  -> "Park Vehicle" appears in the radial menu.
      * Stand anywhere in bounds   -> "Parking Lot" appears, listing your cars.

    A parked car remembers its spot. Pull it back out and it returns to that exact
    spot -- unless something else is sitting there, in which case it takes the next
    open spot in the array.

    Capturing coordinates: set Config.Debug = true, then drive to each spot and use
    /parkspot. /parkbounds walks the outline, /parkdump prints both ready to paste.
]]

Config = {}

-- Debug mode. Draws each lot's bounds as a wireframe, marks every spot green when
-- free and red when a car is sitting on it, labels the lot and each spot, prints a
-- summary of the loaded lots to the console, and enables the coordinate capture
-- commands (/parkbounds, /parkspot, /parkdump, /parkclear).
Config.Debug = true

-- ---------------------------------------------------------------------------
-- Interaction
-- ---------------------------------------------------------------------------

-- Font Awesome 6 solid icon names, as used by qb-radialmenu.
Config.ParkIcon = 'square-parking'
Config.ListIcon = 'car-rear'

Config.ParkTitle = 'Park Vehicle'
Config.ListTitle = 'Parking Lot'

-- How close your vehicle must be to a spot's coords for that spot to count as the
-- one you are sitting in. Roughly half a parking bay.
Config.SpotRadius = 3.0

-- How close ANY vehicle must be to a spot for that spot to count as occupied when
-- deciding where a retrieved car comes out.
Config.SpotOccupiedRadius = 2.5

-- Slack the server allows on top of SpotRadius when it re-checks a park request.
Config.ParkTolerance = 2.5

-- Slack on the "are you actually standing in this lot" check when pulling a car out.
Config.RetrieveTolerance = 5.0

-- How often the client re-checks which spot you are sitting in, while inside a lot.
Config.PollInterval = 300

-- Progress bar shown while parking, in ms. 0 parks instantly.
Config.ParkDuration = 1500

-- Put the player straight into the driver's seat of a retrieved vehicle.
Config.WarpIntoVehicle = true

-- On resource start, mark every vehicle whose garage is a jgrp lot as stored again.
-- Off by default: it rewrites rows other garage scripts may also own.
Config.RestoreOnStart = false

-- ---------------------------------------------------------------------------
-- Server hooks -- these are the only places jgrp-garage touches other resources.
-- ---------------------------------------------------------------------------

function Config.GetFuel(vehicle)
    return exports['sofy-fuel']:GetFuel(vehicle)
end

function Config.SetFuel(vehicle, fuel)
    exports['sofy-fuel']:SetFuel(vehicle, fuel)
end

function Config.GiveKey(plate)
    TriggerEvent('vehiclekeys:client:SetOwner', plate)
end

-- ---------------------------------------------------------------------------
-- Vehicle classes, for the optional per-lot `classes` restriction.
-- ---------------------------------------------------------------------------

Config.VehicleClasses = {
    all       = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22 },
    car       = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 13, 18, 22 },
    air       = { 15, 16 },
    sea       = { 14 },
    rig       = { 10, 11, 17, 19, 20 },
    emergency = { 18, 19 }
}

-- ---------------------------------------------------------------------------
-- Parking lots
-- ---------------------------------------------------------------------------
--
--  label    string    shown on the blip and at the top of the vehicle list
--  bounds   table     either a polygon or a box (see the two examples below)
--  spots    array     vector4(x, y, z, heading) -- one entry per parking bay,
--                     in the order cars should fall back through when full
--  blip     table?    { label, sprite, colour, scale }. Omit it, or set it to
--                     false, and the lot gets no map blip at all.
--  classes  array?    Config.VehicleClasses[...] to restrict what may park here
--
-- POLYGON bounds -- an outline of vector3 points plus a vertical thickness:
--      bounds = { points = { vec3(...), vec3(...), ... }, thickness = 10.0 }
--
-- BOX bounds -- a centre, a size and an optional heading:
--      bounds = { center = vec3(...), size = vec3(30.0, 20.0, 10.0), rotation = 0.0 }
--
Config.Lots = {

    pillbox = {
        label = 'Pillbox Parking',
        bounds = {
            points = {
                vec3(200.0, -788.0, 30.5),
                vec3(240.0, -788.0, 30.5),
                vec3(240.0, -815.0, 30.5),
                vec3(200.0, -815.0, 30.5)
            },
            thickness = 10.0
        },
        spots = {
            vec4(222.02, -804.19, 30.26, 248.19),
            vec4(223.93, -799.11, 30.25, 248.53),
            vec4(226.46, -794.33, 30.24, 248.29),
            vec4(232.33, -807.97, 30.02, 69.17),
            vec4(206.07, -800.93, 30.36, 69.09)
        },
        blip = {
            label = 'Public Parking',
            sprite = 357,
            colour = 3,
            scale = 0.7
        },
        classes = Config.VehicleClasses['car']
    },

    -- Set blip = false, or drop the key entirely, for a lot with no map blip.
    motel = {
        label = 'Motel Parking',
        bounds = {
            center = vec3(270.0, -333.0, 44.7),
            size = vec3(30.0, 20.0, 10.0),
            rotation = 0.0
        },
        spots = {
            vec4(265.96, -332.3, 44.51, 250.68)
        },
        blip = {
            label = 'Public Parking',
            sprite = 357,
            colour = 3,
            scale = 0.7
        },
        classes = Config.VehicleClasses['car']
    }

}

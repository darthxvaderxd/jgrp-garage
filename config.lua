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
-- Off: the car is handed over parked in its spot and you walk to it.
Config.WarpIntoVehicle = false

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
-- POLYGON bounds -- an outline of vec3 points plus a vertical thickness:
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
                vector3(200.0, -788.0, 30.5),
                vector3(240.0, -788.0, 30.5),
                vector3(240.0, -815.0, 30.5),
                vector3(200.0, -815.0, 30.5)
            },
            thickness = 10.0
        },
        spots = {
            vector4(222.02, -804.19, 30.26, 248.19),
            vector4(223.93, -799.11, 30.25, 248.53),
            vector4(226.46, -794.33, 30.24, 248.29),
            vector4(232.33, -807.97, 30.02, 69.17),
            vector4(206.07, -800.93, 30.36, 69.09)
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
    },

    red_garage_floor1 = {
        label = 'Red Garage Floor 1',
       bounds = {
            points = {
               vector3(-289.5, -783.01, 33.96),
               vector3(-284.36, -774.17, 33.96),
               vector3(-275.47, -777.39, 33.96),
               vector3(-266.6, -753.56, 33.96),
               vector3(-310.35, -737.25, 33.96),
               vector3(-312.7, -742.17, 33.96),
               vector3(-359.54, -727.66, 33.97),
               vector3(-362.31, -792.56, 33.97),
               vector3(-336.07, -786.49, 33.96),
               vector3(-319.15, -771.82, 33.96),
               vector3(-290.23, -782.81, 33.96),
            },
            thickness = 10.0
        },
        spots = {
            vector4(-307.4, -772.86, 33.54, 341.1),
            vector4(-310.02, -772.02, 33.54, 339.74),
        },
        blip = {
            label = 'Public Parking',
            sprite = 357,
            colour = 3,
            scale = 0.7
        },
        classes = Config.VehicleClasses['car']
    },

    white_garage_floor1 = {
        label = 'White Garage Floor 1',
        bounds = {
             points = {
                vector3(-480.31, -819.22, 30.42),
                vector3(-441.16, -820.21, 30.81),
                vector3(-441.0, -796.3, 30.73),
                vector3(-450.24, -796.05, 30.54),
                vector3(-450.24, -796.05, 30.54),
                vector3(-443.18, -781.56, 30.6),
                vector3(-443.65, -753.36, 30.56),
                vector3(-469.63, -753.42, 30.56),
                vector3(-469.99, -733.5, 30.56),
                vector3(-480.39, -733.23, 30.56),
                vector3(-480.33, -791.75, 30.6),
                vector3(-480.38, -816.45, 30.67),
             },
             thickness = 10.0
        },
        spots = {
            vector4(-476.95, -809.94, 29.9, 270.36),
            vector4(-477.31, -806.77, 29.9, 268.83),
            vector4(-476.9, -803.7, 29.9, 268.92),
            vector4(-477.11, -800.68, 29.91, 271.34),
            vector4(-477.27, -797.28, 29.91, 269.33),
            vector4(-477.37, -794.06, 29.91, 269.29),
            vector4(-467.14, -797.2, 29.91, 91.41),
            vector4(-467.15, -800.48, 29.9, 91.56),
            vector4(-467.05, -803.53, 29.9, 87.72),
            vector4(-467.22, -806.59, 29.9, 88.12),
            vector4(-459.96, -806.97, 29.9, 265.3),
            vector4(-459.85, -803.67, 29.9, 271.46),
            vector4(-459.45, -800.24, 29.9, 270.01),
            vector4(-459.64, -797.37, 29.9, 268.25),
            vector4(-460.58, -794.16, 29.91, 268.67),
            vector4(-444.74, -808.82, 29.9, 89.51),
            vector4(-445.26, -804.8, 29.9, 91.19),
            vector4(-445.14, -801.19, 29.9, 90.63),
            vector4(-444.58, -797.84, 29.91, 93.78),
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

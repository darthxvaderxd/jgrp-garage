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
Config.Debug = false

-- ---------------------------------------------------------------------------
-- Interaction
-- ---------------------------------------------------------------------------

-- Font Awesome 6 solid icon names, as used by qb-radialmenu.
Config.ParkIcon = 'square-parking'
Config.ListIcon = 'car-rear'

Config.ParkTitle = 'Park Vehicle'
Config.ListTitle = 'Parking Lot'

-- What the same option is called at an impound lot, where it lists what the
-- police have towed rather than what you parked.
Config.ImpoundTitle = 'Impound Lot'
Config.ImpoundIcon = 'money-bill'

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
--
-- Mutually exclusive with Config.ImpoundOnStart below -- one puts cars back in
-- their lots, the other puts them in the pound, and they cannot both be right.
-- Impounding wins if both are on.
Config.RestoreOnStart = false

-- On resource start, impound every vehicle left out in the world.
--
-- A restart leaves owned cars that were driving around with nowhere to be:
-- nobody parked them, and the vehicle entities are gone. Impounding them is
-- what qb-garages did, and it is the honest outcome -- the car was not put
-- away, so it gets towed, and the owner pays to get it back.
--
-- Only rows that are actually out (`state = 0`) are touched, and a fee the
-- police already set is never overwritten -- being impounded twice should not
-- make a car cheaper or dearer to release.
Config.ImpoundOnStart = true

-- What the tow costs. Separate from Config.ImpoundFallbackPrice, which is for a
-- police impound that arrived without a fee -- this one is the restart tow, and
-- servers usually want it cheaper than a seizure.
Config.ImpoundOnStartPrice = 250

-- ---------------------------------------------------------------------------
-- Integration hooks -- the only places jgrp-garage touches other resources.
-- All three run CLIENT-side (client/main.lua), so they have access to the
-- vehicle entity but not to a player's server id.
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
--  impound  boolean?  makes this lot the impound instead of a parking lot --
--                     see the impound lot at the bottom of this file
--
-- POLYGON bounds -- an outline of vec3 points plus a vertical thickness:
--      bounds = { points = { vec3(...), vec3(...), ... }, thickness = 10.0 }
--
-- BOX bounds -- a centre, a size and an optional heading:
--      bounds = { center = vec3(...), size = vec3(30.0, 20.0, 10.0), rotation = 0.0 }
--
--- What the impound charges when the police did not set a fee -- a vehicle with
--- no `depotprice` on it. qb-policejob normally sets one per impound; this is
--- only the floor for rows that arrived without.
Config.ImpoundFallbackPrice = 500

Config.Lots = {

    pillbox = {
        label = 'Pillbox Parking',
        bounds = {
            points = {
                vector3(201.67, -804.84, 31.06),
                vector3(239.12, -818.58, 30.19),
                vector3(257.62, -767.73, 30.79),
                vector3(219.52, -756.2, 30.83),
            },
            thickness = 10.0
        },
        spots = {
            vector4(206.19, -801.05, 30.58, 248.76),
            vector4(207.4, -798.62, 30.56, 250.4),
            vector4(208.39, -796.17, 30.54, 248.27),
            vector4(209.2, -793.72, 30.52, 248.2),
            vector4(210.22, -791.24, 30.5, 247.13),
            vector4(211.23, -788.84, 30.48, 249.08),
            vector4(211.77, -786.0, 30.48, 249.02),
            vector4(212.87, -783.85, 30.46, 247.99),
            vector4(213.82, -781.23, 30.45, 247.55),
            vector4(214.74, -778.57, 30.44, 248.45),
            vector4(215.93, -776.16, 30.42, 250.29),
            vector4(216.49, -773.47, 30.42, 251.02),
            vector4(217.43, -771.16, 30.41, 248.82),
            vector4(218.65, -768.52, 30.41, 250.66),
            vector4(219.17, -765.88, 30.41, 249.83),
            vector4(227.3, -768.57, 30.37, 69.44),
            vector4(226.94, -771.43, 30.36, 70.07),
            vector4(225.28, -773.46, 30.36, 69.12),
            vector4(224.49, -776.24, 30.35, 69.71),
            vector4(224.02, -778.93, 30.34, 71.69),
            vector4(222.77, -781.46, 30.34, 69.47),
            vector4(222.66, -784.11, 30.34, 70.57),
            vector4(221.75, -786.6, 30.35, 65.95),
            vector4(220.06, -788.85, 30.35, 69.38),
            vector4(218.93, -791.19, 30.35, 72.02),
            vector4(218.19, -793.8, 30.35, 68.56),
            vector4(217.08, -796.44, 30.37, 69.02),
            vector4(216.13, -798.75, 30.38, 66.64),
            vector4(215.54, -801.35, 30.39, 71.47),
            vector4(214.29, -803.95, 30.41, 68.32),
            vector4(220.55, -809.25, 30.24, 247.73),
            vector4(221.42, -806.79, 30.25, 250.89),
            vector4(222.71, -804.37, 30.24, 247.46),
            vector4(223.42, -801.95, 30.23, 250.04),
            vector4(224.3, -799.3, 30.23, 249.01),
            vector4(225.38, -796.88, 30.23, 248.22),
            vector4(226.15, -794.27, 30.24, 250.15),
            vector4(226.9, -791.57, 30.25, 251.38),
            vector4(228.01, -789.17, 30.25, 249.06),
            vector4(229.03, -786.71, 30.26, 250.63),
            vector4(230.24, -784.3, 30.27, 248.02),
            vector4(231.28, -781.79, 30.27, 248.56),
            vector4(232.14, -779.34, 30.28, 250.18),
            vector4(232.7, -776.52, 30.3, 250.79),
            vector4(234.24, -774.19, 30.31, 248.22),
            vector4(234.56, -771.54, 30.33, 247.31),
            vector4(244.58, -772.09, 30.29, 68.08),
            vector4(243.52, -774.62, 30.27, 68.41),
            vector4(242.5, -777.05, 30.24, 68.15),
            vector4(241.86, -779.87, 30.2, 68.2),
            vector4(240.54, -782.15, 30.19, 68.45),
            vector4(240.17, -784.95, 30.16, 69.67),
            vector4(238.37, -790.15, 30.11, 70.99),
            vector4(237.5, -792.5, 30.09, 67.76),
            vector4(235.82, -794.73, 30.1, 65.85),
            vector4(235.05, -797.5, 30.08, 68.0),
            vector4(234.07, -799.77, 30.07, 67.81),
            vector4(233.08, -802.43, 30.06, 70.84),
            vector4(231.73, -804.71, 30.06, 69.36),
            vector4(230.86, -807.29, 30.05, 68.11),
            vector4(230.3, -810.17, 30.03, 70.45),
        },
        blip = {
            label = 'Public Parking',
            sprite = 357,
            colour = 3,
            scale = 0.7
        },
        classes = Config.VehicleClasses['car']
    },


    pillbox_garage = {
        label = 'Pillbox Garage Parking',
        bounds = {
            points = {
                vector3(265.17, -767.43, 30.9),
                vector3(220.36, -751.19, 30.82),
                vector4(226.44, -733.07, 30.81, 2.7),
                vector3(271.99, -748.68, 30.82),

            },
            thickness = 10.0
        },
        spots = {
            vector4(233.61, -739.4, 34.15, 160.97),
            vector4(237.1, -741.03, 34.17, 159.91),
            vector4(240.37, -742.15, 34.19, 157.26),
            vector4(243.52, -743.1, 34.2, 161.83),
            vector4(246.78, -743.96, 34.2, 160.34),
            vector4(250.11, -745.16, 34.21, 159.6),
            vector4(253.42, -746.8, 34.21, 159.7),
            vector4(263.57, -758.88, 34.22, 69.69),
            vector4(262.55, -762.53, 34.22, 72.66),
            vector4(255.11, -760.73, 34.22, 339.34),
            vector4(252.06, -759.12, 34.22, 340.77),
            vector4(248.69, -757.69, 34.22, 338.6),
            vector4(245.38, -756.69, 34.21, 340.35),
            vector4(245.53, -742.9, 30.4, 163.3),
            vector4(248.6, -744.01, 30.4, 159.94),
            vector4(252.05, -744.9, 30.4, 159.06),
            vector4(255.25, -746.38, 30.4, 159.5),
            vector4(258.63, -747.32, 30.4, 162.62),
            vector4(261.69, -748.67, 30.39, 158.96),
            vector4(264.95, -749.77, 30.39, 159.48),
            vector4(268.59, -750.7, 30.39, 156.94),
            vector4(264.07, -764.36, 30.4, 339.71),
            vector4(261.1, -762.63, 30.4, 338.03),
            vector4(257.7, -761.83, 30.4, 341.31),
            vector4(254.75, -760.44, 30.4, 336.42),
            vector4(251.24, -759.79, 30.4, 338.47),
            vector4(247.54, -757.8, 30.4, 340.98),
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
    pink_cage_parking = {
        label = 'Pink Cage Parking',
        bounds = {
            points = {
                vector3(336.0, -221.14, 54.29),
                vector3(341.72, -206.78, 54.09),
                vector3(315.37, -196.76, 54.22),
                vector3(311.28, -210.45, 54.09),
                vector3(330.69, -218.79, 54.09)
            },
        },
        spots = {
            vector4(334.18, -216.91, 53.66, 68.73),
            vector4(334.91, -213.4, 53.66, 71.05),
            vector4(336.55, -210.69, 53.66, 69.37),
            vector4(337.33, -207.14, 53.66, 68.39),
            vector4(314.61, -209.7, 53.66, 250.34),
            vector4(316.3, -206.39, 53.66, 248.12),
            vector4(317.07, -202.96, 53.66, 249.22),
            vector4(318.58, -199.87, 53.66, 244.57),
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
    rockford_garage = {
        label = 'Rockford Garage',
        bounds = {
            points = {
                vector3(-1132.4, -774.76, 17.99),
                vector3(-1118.13, -762.87, 19.11),
                vector3(-1140.42, -733.05, 20.45),
                vector3(-1152.49, -744.09, 19.63),
            },
        },
        spots = {
            vector4(-1146.0, -746.03, 19.2, 112.34),
            vector4(-1143.43, -748.5, 19.08, 111.71),
            vector4(-1141.3, -751.62, 18.93, 107.32),
            vector4(-1138.69, -754.47, 18.79, 109.22),
            vector4(-1136.0, -757.48, 18.64, 108.37),
            vector4(-1134.01, -760.45, 18.47, 107.76),
            vector4(-1131.43, -763.83, 18.29, 112.37),
            vector4(-1126.91, -758.45, 18.75, 288.91),
            vector4(-1129.99, -755.41, 18.89, 288.62),
            vector4(-1131.7, -752.34, 19.05, 289.46),
            vector4(-1134.98, -749.6, 19.17, 290.43),
            vector4(-1136.63, -746.84, 19.3, 290.15),
            vector4(-1139.7, -743.81, 19.44, 289.16),
            vector4(-1142.22, -740.98, 19.59, 288.76),
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
            vector4(-313.29, -771.54, 33.32, 340.64),
            vector4(-315.76, -770.38, 33.33, 340.08),
            vector4(-290.2, -764.13, 33.33, 338.57),
            vector4(-292.84, -763.23, 33.33, 339.57),
            vector4(-295.43, -762.06, 33.33, 338.1),
            vector4(-298.27, -761.2, 33.33, 341.31),
            vector4(-302.24, -759.44, 33.33, 339.19),
            vector4(-305.21, -758.36, 33.33, 340.93),
            vector4(-308.22, -757.54, 33.33, 340.23),
            vector4(-310.75, -756.42, 33.33, 341.42),
            vector4(-314.96, -754.88, 33.33, 337.9),
            vector4(-317.54, -753.64, 33.54, 338.06),
            vector4(-320.45, -752.6, 33.54, 340.88),
            vector4(-323.12, -752.06, 33.54, 338.23),
            vector4(-328.83, -750.76, 33.54, 359.59),
            vector4(-331.92, -750.27, 33.54, 0.94),
            vector4(-337.62, -750.88, 33.54, 358.63),
            vector4(-277.57, -775.0, 33.54, 67.04),
            vector4(-276.35, -771.65, 33.54, 71.77),
            vector4(-275.32, -768.24, 33.54, 71.22),
            vector4(-273.73, -764.93, 33.54, 72.54),
            vector4(-272.82, -761.57, 33.54, 69.56),
            vector4(-277.31, -752.12, 33.54, 161.83),
            vector4(-280.22, -751.34, 33.54, 160.56),
            vector4(-284.73, -749.48, 33.54, 158.54),
            vector4(-287.39, -748.18, 33.54, 158.71),
            vector4(-290.06, -747.38, 33.54, 159.96),
            vector4(-293.19, -746.27, 33.54, 161.48),
            vector4(-297.14, -745.0, 33.54, 160.24),
            vector4(-300.1, -743.51, 33.54, 162.59),
            vector4(-302.77, -743.0, 33.54, 160.53),
            vector4(-342.18, -749.55, 33.54, 89.65),
            vector4(-342.37, -753.52, 33.54, 91.6),
            vector4(-342.31, -756.98, 33.55, 92.9),
            vector4(-342.39, -760.27, 33.54, 90.05),
            vector4(-342.06, -764.25, 33.54, 92.24),
            vector4(-341.96, -767.71, 33.54, 92.79),
            vector4(-357.08, -764.46, 33.54, 269.11),
            vector4(-356.82, -759.92, 33.54, 270.46),
            vector4(-356.69, -756.78, 33.54, 268.31),
            vector4(-356.92, -753.69, 33.54, 269.73),
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
    },

    spanish_garage = {
        label = 'Spanish Garage',
        bounds = {
             points = {
                vector3(51.59, 18.47, 69.66),
                vector3(66.26, 13.05, 69.03),
                vector3(69.5, 25.77, 69.52),
                vector3(57.07, 29.59, 70.1),
             },
             thickness = 10.0
        },
        spots = {
            vector4(54.61, 19.94, 68.95, 336.49),
            vector4(57.73, 18.79, 68.72, 339.78),
            vector4(60.96, 17.74, 68.6, 341.24),
            vector4(64.0, 17.01, 68.56, 337.48),
        },
        blip = {
            label = 'Public Parking',
            sprite = 357,
            colour = 3,
            scale = 0.7
        },
        classes = Config.VehicleClasses['car']
    },

    casino_garage = {
        label = 'Casino Garage',
        bounds = {
             points = {
                vector3(943.11, -31.53, 78.76),
                vector3(872.31, 12.79, 78.89),
                vector3(832.02, -48.95, 78.9),
                vector3(916.12, -107.28, 78.89),
                vector3(928.2, -106.11, 78.86),
                vector3(942.04, -93.51, 78.86),
                vector3(945.98, -83.12, 78.9),
                vector3(940.88, -71.88, 78.86),
                vector3(935.68, -64.38, 78.85),
                vector3(937.41, -56.95, 78.88),
                vector3(945.96, -42.7, 78.9),
             },
             thickness = 10.0
        },
        spots = {
            vector4(872.31, 8.44, 78.34, 144.57),
             vector4(875.51, 7.44, 78.34, 149.99),
             vector4(878.29, 5.38, 78.34, 149.54),
             vector4(931.47, -28.09, 78.34, 147.52),
             vector4(934.21, -29.5, 78.34, 144.35),
             vector4(937.36, -31.57, 78.34, 148.7),
             vector4(940.21, -33.0, 78.34, 147.02),
             vector4(942.24, -42.63, 78.34, 56.81),
             vector4(940.91, -45.69, 78.34, 58.27),
             vector4(938.66, -48.46, 78.34, 58.43),
             vector4(936.76, -51.51, 78.34, 61.55),
             vector4(935.41, -54.56, 78.34, 59.63),
             vector4(933.12, -58.17, 78.34, 73.07),
             vector4(932.36, -62.56, 78.34, 85.24),
             vector4(932.76, -67.16, 78.34, 104.02),
             vector4(935.24, -72.3, 78.34, 132.76),
             vector4(938.08, -74.3, 78.34, 136.28),
             vector4(940.67, -77.81, 78.34, 125.81),
             vector4(942.56, -82.13, 78.34, 96.73),
             vector4(941.88, -87.26, 78.34, 75.45),
             vector4(938.74, -91.76, 78.34, 43.31),
             vector4(936.13, -93.89, 78.34, 42.12),
             vector4(933.86, -96.5, 78.34, 42.05),
             vector4(931.23, -98.89, 78.34, 46.97),
             vector4(928.63, -100.75, 78.34, 46.69),
             vector4(924.84, -103.68, 78.34, 23.48),
             vector4(919.72, -104.28, 78.34, 2.41),
             vector4(912.34, -101.11, 78.34, 327.3),
             vector4(909.39, -99.53, 78.34, 327.66),
             vector4(906.43, -97.69, 78.34, 327.18),
             vector4(903.31, -95.53, 78.34, 328.83),
             vector4(900.73, -93.7, 78.34, 328.22),
             vector4(897.95, -91.8, 78.34, 328.8),
             vector4(894.64, -90.43, 78.34, 329.24),
             vector4(874.09, -77.54, 78.34, 327.72),
             vector4(871.43, -75.45, 78.34, 328.69),
             vector4(868.31, -73.94, 78.34, 329.58),
             vector4(865.54, -72.25, 78.34, 327.8),
             vector4(862.51, -70.14, 78.34, 332.22),
             vector4(859.7, -68.18, 78.34, 326.44),
             vector4(856.85, -66.38, 78.34, 325.51),
             vector4(853.88, -64.86, 78.34, 325.38),
             vector4(850.75, -62.44, 78.34, 317.43),
             vector4(848.08, -60.24, 78.34, 318.1),
             vector4(845.73, -57.73, 78.34, 318.78),
             vector4(843.03, -55.2, 78.34, 317.18),
             vector4(840.73, -52.4, 78.34, 315.03),
             vector4(838.15, -50.39, 78.34, 312.33),
             vector4(835.52, -47.78, 78.34, 316.39),
             vector4(844.55, -36.58, 78.34, 59.64),
             vector4(846.52, -33.52, 78.34, 57.33),
             vector4(848.36, -30.88, 78.34, 59.85),
             vector4(852.0, -25.03, 78.34, 58.5),
             vector4(853.33, -21.93, 78.34, 56.7),
             vector4(855.46, -18.92, 78.34, 58.09),
             vector4(857.42, -16.12, 78.34, 58.87),
             vector4(871.87, -9.08, 78.34, 236.76),
             vector4(869.88, -11.84, 78.34, 237.45),
             vector4(868.32, -14.89, 78.34, 241.04),
             vector4(866.51, -17.86, 78.34, 238.23),
             vector4(864.83, -20.75, 78.34, 238.98),
             vector4(863.03, -23.86, 78.34, 237.65),
             vector4(860.91, -26.81, 78.34, 238.06),
             vector4(859.11, -29.68, 78.34, 237.02),
             vector4(857.34, -32.58, 78.34, 238.9),
             vector4(855.11, -35.27, 78.34, 238.78),
             vector4(853.96, -38.33, 78.34, 239.6),
             vector4(851.36, -40.81, 78.34, 238.5),
             vector4(860.63, -50.82, 78.34, 57.74),
             vector4(862.47, -47.71, 78.34, 57.66),
             vector4(864.63, -45.04, 78.34, 59.08),
             vector4(866.6, -42.06, 78.34, 56.77),
             vector4(867.71, -38.77, 78.34, 58.86),
             vector4(870.18, -36.67, 78.34, 60.37),
             vector4(872.18, -33.71, 78.34, 58.68),
             vector4(874.05, -30.63, 78.34, 60.56),
             vector4(875.96, -27.82, 78.34, 61.51),
             vector4(877.48, -24.59, 78.34, 60.72),
             vector4(879.21, -21.7, 78.34, 59.42),
             vector4(880.75, -18.49, 78.34, 57.96),
             vector4(882.93, -15.92, 78.34, 59.79),
             vector4(889.83, -20.29, 78.34, 238.62),
             vector4(887.75, -23.01, 78.34, 240.67),
             vector4(885.69, -25.73, 78.34, 238.13),
             vector4(884.12, -28.94, 78.34, 237.87),
             vector4(882.3, -31.6, 78.34, 240.93),
             vector4(880.8, -34.89, 78.34, 242.9),
             vector4(878.48, -37.6, 78.34, 241.56),
             vector4(876.85, -40.49, 78.34, 239.02),
             vector4(875.28, -43.53, 78.34, 238.59),
             vector4(873.3, -46.37, 78.34, 239.5),
             vector4(871.09, -49.1, 78.34, 239.86),
             vector4(869.58, -52.5, 78.34, 241.09),
             vector4(868.37, -55.64, 78.34, 237.72),
             vector4(878.81, -62.07, 78.34, 59.54),
             vector4(881.15, -59.52, 78.34, 57.3),
             vector4(883.47, -56.8, 78.34, 61.68),
             vector4(884.79, -53.64, 78.34, 59.15),
             vector4(886.56, -50.68, 78.34, 60.49),
             vector4(888.29, -47.85, 78.34, 57.46),
             vector4(889.82, -44.43, 78.34, 57.69),
             vector4(892.11, -41.98, 78.34, 61.59),
             vector4(893.77, -39.11, 78.34, 61.56),
             vector4(895.32, -36.1, 78.34, 59.42),
             vector4(897.02, -32.83, 78.34, 59.26),
             vector4(899.1, -30.22, 78.34, 57.79),
             vector4(900.3, -26.85, 78.34, 58.19),
             vector4(908.38, -31.76, 78.34, 239.22),
             vector4(906.31, -34.7, 78.34, 239.62),
             vector4(904.21, -37.28, 78.34, 240.64),
             vector4(902.62, -40.42, 78.34, 239.62),
             vector4(900.89, -43.46, 78.34, 240.93),
             vector4(898.89, -46.17, 78.34, 239.35),
             vector4(897.4, -49.35, 78.34, 239.7),
             vector4(895.5, -52.21, 78.34, 240.14),
             vector4(893.16, -54.81, 78.34, 239.44),
             vector4(891.88, -58.26, 78.34, 236.48),
             vector4(890.04, -61.12, 78.34, 236.73),
             vector4(888.24, -63.85, 78.34, 239.22),
             vector4(885.93, -66.27, 78.34, 238.55),
             vector4(897.49, -73.66, 78.34, 58.58),
             vector4(899.18, -70.67, 78.34, 62.02),
             vector4(901.02, -67.95, 78.34, 56.88),
             vector4(902.81, -64.71, 78.34, 60.31),
             vector4(904.65, -61.99, 78.34, 58.53),
             vector4(906.61, -59.16, 78.34, 59.71),
             vector4(908.76, -56.38, 78.34, 60.59),
             vector4(910.6, -53.68, 78.34, 59.03),
             vector4(912.22, -50.42, 78.34, 57.77),
             vector4(913.82, -47.44, 78.34, 58.03),
             vector4(915.72, -44.62, 78.34, 61.28),
             vector4(918.05, -41.89, 78.34, 60.02),
             vector4(919.14, -38.57, 78.34, 59.16),
             vector4(926.39, -43.12, 78.34, 235.56),
             vector4(924.28, -45.8, 78.34, 241.78),
             vector4(922.74, -49.01, 78.34, 237.54),
             vector4(921.06, -52.03, 78.34, 237.46),
             vector4(919.29, -55.01, 78.34, 240.29),
             vector4(917.53, -57.61, 78.34, 239.12),
             vector4(915.43, -60.95, 78.34, 235.81),
             vector4(913.41, -63.31, 78.34, 241.23),
             vector4(912.45, -66.88, 78.34, 238.62),
             vector4(909.8, -69.29, 78.34, 243.01),
             vector4(907.88, -72.14, 78.34, 241.44),
             vector4(906.32, -75.16, 78.34, 239.25),
             vector4(904.36, -78.1, 78.34, 238.26),
             vector4(916.72, -84.58, 78.34, 59.52),
             vector4(917.89, -81.4, 78.34, 56.89),
             vector4(920.28, -78.76, 78.34, 60.88),
             vector4(927.09, -83.18, 78.34, 238.02),
             vector4(924.9, -85.79, 78.34, 238.14),
             vector4(923.4, -89.13, 78.34, 238.67),
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
    beach_garage = {
        label = 'Beach Garage',
        bounds = {
            points = {
                vector3(-1189.17, -1509.48, 4.38),
                vector3(-1207.88, -1481.53, 4.36),
                vector3(-1196.77, -1470.69, 4.38),
                vector3(-1186.82, -1462.43, 4.38),
                vector3(-1168.22, -1489.62, 4.38),
                vector3(-1176.13, -1501.35, 4.38),
            },
        },
        spots = {
            vector4(-1191.27, -1504.04, 3.95, 306.01),
            vector4(-1196.25, -1496.95, 3.94, 303.77),
            vector4(-1198.29, -1494.52, 3.94, 302.54),
            vector4(-1200.12, -1491.45, 3.94, 301.6),
            vector4(-1204.49, -1485.0, 3.94, 304.3),
            vector4(-1193.97, -1480.34, 3.96, 125.62),
            vector4(-1192.05, -1482.97, 3.96, 125.85),
            vector4(-1190.61, -1485.63, 3.95, 124.22),
            vector4(-1188.22, -1488.13, 3.95, 123.97),
            vector4(-1186.62, -1490.7, 3.96, 125.68),
            vector4(-1185.19, -1493.39, 3.96, 123.17),
            vector4(-1183.19, -1495.91, 3.96, 122.96),
            vector4(-1176.51, -1491.45, 3.96, 304.35),
            vector4(-1178.87, -1488.82, 3.96, 306.53),
            vector4(-1180.31, -1486.49, 3.96, 304.25),
            vector4(-1182.25, -1483.79, 3.96, 307.6),
            vector4(-1185.07, -1480.34, 3.96, 301.21),
            vector4(-1187.69, -1476.0, 3.96, 302.58),
            vector4(-1189.89, -1473.2, 3.96, 307.64),
            vector4(-1192.04, -1470.42, 3.96, 301.22),
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
    clinton_garage = {
        label = 'Clinton Garage',
        bounds = {
            points = {
                vector3(359.13, 302.21, 103.88),
                vector3(351.96, 270.84, 103.02),
                vector3(387.35, 258.69, 103.01),
                vector3(398.52, 291.17, 103.34),
                vector3(375.46, 297.85, 103.29),
            },
        },
        spots = {
            vector4(375.12, 294.17, 102.84, 161.72),
            vector4(378.66, 293.67, 102.78, 160.9),
            vector4(383.05, 292.51, 102.69, 164.73),
            vector4(386.92, 290.9, 102.62, 161.94),
            vector4(390.66, 289.24, 102.57, 160.72),
            vector4(393.52, 283.65, 102.55, 76.25),
            vector4(392.31, 280.6, 102.56, 73.48),
            vector4(390.73, 276.66, 102.57, 70.16),
            vector4(389.07, 273.3, 102.58, 70.74),
            vector4(388.04, 269.75, 102.58, 70.14),
            vector4(379.2, 264.54, 102.59, 339.8),
            vector4(375.52, 266.04, 102.59, 333.78),
            vector4(371.77, 267.32, 102.61, 338.77),
            vector4(367.97, 268.94, 102.63, 338.38),
            vector4(363.9, 270.26, 102.64, 338.52),
            vector4(359.88, 271.96, 102.67, 343.69),
            vector4(357.45, 282.31, 102.97, 245.84),
            vector4(358.75, 286.1, 103.06, 245.21),
            vector4(360.16, 290.0, 103.07, 249.29),
            vector4(370.95, 284.77, 102.84, 347.63),
            vector4(374.93, 283.74, 102.76, 335.84),
            vector4(378.59, 282.29, 102.69, 343.63),
            vector4(376.18, 274.53, 102.65, 163.17),
            vector4(372.03, 275.05, 102.7, 162.87),
            vector4(368.17, 276.49, 102.76, 162.34),
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
    mirror_park_garage = {
        label = 'Mirror Park Garage',
        bounds = {
            points = {
               vector3(1022.07, -750.36, 58.01),
               vector3(1005.95, -764.61, 58.0),
               vector3(1030.6, -795.58, 57.99),
               vector3(1049.24, -794.48, 58.21),
               vector3(1051.11, -768.47, 58.31),
               vector3(1025.79, -754.72, 57.98),
            },
        },
        spots = {
            vector4(1023.18, -755.41, 57.53, 228.18),
            vector4(1020.11, -758.09, 57.57, 228.02),
            vector4(1016.99, -760.7, 57.54, 217.85),
            vector4(1014.72, -763.37, 57.47, 223.69),
            vector4(1016.09, -770.78, 57.48, 309.54),
            vector4(1018.52, -773.36, 57.49, 306.55),
            vector4(1020.73, -776.13, 57.47, 313.92),
            vector4(1023.0, -779.19, 57.46, 313.73),
            vector4(1025.37, -782.28, 57.45, 311.09),
            vector4(1028.07, -785.08, 57.46, 310.06),
            vector4(1029.97, -788.08, 57.44, 310.55),
            vector4(1038.12, -791.18, 57.53, 4.95),
            vector4(1041.94, -791.67, 57.57, 4.1),
            vector4(1046.81, -785.65, 57.57, 91.65),
            vector4(1046.64, -782.05, 57.58, 89.61),
            vector4(1046.63, -778.35, 57.58, 95.47),
            vector4(1046.67, -774.48, 57.59, 94.38),
            vector4(1031.32, -773.15, 57.64, 144.09),
            vector4(1028.06, -771.21, 57.61, 147.26),
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
    occupation_garage = {
        label = 'Occupation Garage',
        bounds = {
            points = {
                vector3(295.14, -354.38, 45.02),
                vector3(304.0, -329.45, 45.04),
                vector3(268.09, -316.08, 45.01),
                vector3(261.14, -335.01, 44.92),
                vector3(268.37, -337.68, 44.92),
                vector3(266.25, -343.26, 44.92),
            },
        },
        spots = {
            vector4(265.95, -332.31, 44.09, 250.00),
            vector4(267.67, -328.95, 44.08, 250.00),
            vector4(268.89, -325.84, 44.08, 250.00),
            vector4(270.11, -322.5, 44.08, 250.00),
            vector4(271.11, -319.28, 44.08, 250.00),
            vector4(277.0, -339.97, 44.08, 70.00),
            vector4(278.83, -336.89, 44.08, 70.00),
            vector4(280.72, -330.25, 44.08, 70.00),
            vector4(281.97, -327.02, 44.08, 70.00),
            vector4(283.14, -323.88, 44.08, 70.00),
            vector4(283.24, -342.3, 44.08, 250.00),
            vector4(284.56, -339.08, 44.08, 250.00),
            vector4(286.08, -335.97, 44.08, 250.00),
            vector4(286.84, -332.51, 44.08, 250.00),
            vector4(288.24, -329.48, 44.08, 250.00),
            vector4(289.23, -326.02, 44.08, 250.00),
            vector4(292.92, -349.39, 44.1, 70.00),
            vector4(294.12, -346.23, 44.08, 70.00),
            vector4(295.43, -343.11, 44.08, 70.00),
            vector4(296.73, -339.73, 44.08, 70.00),
            vector4(297.56, -336.46, 44.08, 70.00),
            vector4(298.71, -333.37, 44.08, 70.00),
            vector4(300.08, -330.19, 44.08, 70.00)
        },
        blip = {
            label = 'Public Parking',
            sprite = 357,
            colour = 3,
            scale = 0.7
        },
        classes = Config.VehicleClasses['car']
    },

    route_68_motel = {
        label = 'Route 68 Motel',
        bounds = {
             points = {
                vector3(1091.32, 2677.26, 38.73),
                vector3(1140.13, 2674.4, 38.19),
                vector3(1140.31, 2644.54, 38.0),
                vector3(1108.82, 2644.31, 38.14),
                vector3(1108.78, 2660.12, 37.99),
                vector3(1090.23, 2660.07, 37.73)
             },
             thickness = 10.0
        },
        spots = {
            vector4(1135.42, 2647.4, 37.16, 0.00),
            vector4(1131.52, 2647.8, 37.16, 0.00),
            vector4(1124.05, 2647.67, 37.16, 0.00),
            vector4(1120.5, 2647.28, 37.16, 0.00),
            vector4(1116.81, 2647.55, 37.16, 0.00),
            vector4(1111.93, 2654.2, 37.16, 270.00),
            vector4(1111.77, 2657.67, 37.16, 270.00),
            vector4(1105.5, 2662.92, 37.14, 0.00),
            vector4(1101.74, 2663.16, 37.14, 0.00),
            vector4(1098.07, 2663.15, 37.14, 0.00)
        },
        blip = {
            label = 'Public Parking',
            sprite = 357,
            colour = 3,
            scale = 0.7
        },
        classes = Config.VehicleClasses['car']
    },

    great_ocean_parking = {
        label = 'Great Ocean Parking',
        bounds = {
             points = {
                vector3(112.67, 6377.14, 31.23),
                vector3(94.37, 6395.45, 31.23),
                vector3(85.19, 6386.39, 31.23),
                vector3(80.21, 6390.49, 31.23),
                vector3(85.72, 6396.85, 31.23),
                vector3(67.11, 6414.71, 31.23),
                vector3(53.95, 6401.82, 31.23),
                vector3(59.17, 6396.32, 31.23),
                vector3(55.67, 6392.77, 31.23),
                vector3(50.0, 6398.32, 31.23),
                vector3(32.25, 6380.3, 31.23),
                vector3(35.95, 6375.85, 31.23),
                vector3(31.74, 6371.81, 31.23),
                vector3(27.49, 6375.9, 31.23),
                vector3(3.24, 6350.4, 31.23),
                vector3(7.73, 6345.43, 31.23),
                vector3(4.01, 6341.79, 31.23),
                vector3(-0.67, 6346.15, 31.23),
                vector3(-25.81, 6322.0, 31.38),
                vector3(-11.2, 6304.42, 31.23),
                vector3(71.31, 6349.14, 31.23),
                vector3(68.13, 6355.63, 31.23),
                vector3(68.13, 6355.63, 31.23)
             },
             thickness = 10.0
        },
        spots = {
            vector4(101.88, 6376.2, 30.39, 12.16),
            vector4(98.43, 6374.69, 30.39, 16.62),
            vector4(94.94, 6372.49, 30.39, 13.66),
            vector4(80.65, 6366.53, 30.39, 14.05),
            vector4(77.19, 6365.02, 30.39, 15.62),
            vector4(73.62, 6362.68, 30.39, 14.82),
            vector4(70.19, 6361.39, 30.39, 14.67),
            vector4(81.28, 6396.17, 30.39, 132.42),
            vector4(78.53, 6398.72, 30.39, 135.37),
            vector4(75.04, 6401.14, 30.39, 133.03),
            vector4(72.58, 6404.28, 30.39, 133.43),
            vector4(64.46, 6406.85, 30.39, 211.37),
            vector4(61.75, 6403.79, 30.39, 216.95),
            vector4(58.91, 6401.2, 30.39, 210.43),
            vector4(66.45, 6379.77, 30.4, 35.61),
            vector4(63.31, 6377.3, 30.4, 33.13),
            vector4(60.11, 6375.15, 30.4, 32.22),
            vector4(54.33, 6368.21, 30.4, 213.81),
            vector4(51.66, 6365.04, 30.4, 211.77),
            vector4(48.57, 6362.41, 30.4, 210.29),
            vector4(50.63, 6393.65, 30.39, 214.19),
            vector4(47.77, 6390.93, 30.39, 216.3),
            vector4(45.31, 6387.94, 30.39, 214.77),
            vector4(42.64, 6385.02, 30.39, 210.36),
            vector4(40.06, 6382.06, 30.39, 210.06),
            vector4(36.92, 6379.66, 30.39, 211.27),
            vector4(39.53, 6358.82, 30.4, 26.82),
            vector4(37.0, 6355.96, 30.4, 28.15),
            vector4(33.96, 6353.55, 30.4, 32.68),
            vector4(30.58, 6351.42, 30.4, 28.86),
            vector4(27.91, 6348.64, 30.4, 29.17),
            vector4(25.13, 6345.84, 30.4, 31.63),
            vector4(27.38, 6369.93, 30.39, 218.8),
            vector4(24.96, 6366.98, 30.39, 215.68),
            vector4(22.42, 6363.72, 30.39, 210.18),
            vector4(19.35, 6361.52, 30.4, 216.65),
            vector4(16.9, 6358.36, 30.39, 215.56),
            vector4(13.84, 6355.86, 30.39, 213.3),
            vector4(11.57, 6352.21, 30.39, 215.13),
            vector4(8.56, 6350.57, 30.39, 216.71),
            vector4(37.99, 6336.75, 30.39, 16.79),
            vector4(34.57, 6334.96, 30.39, 18.47),
            vector4(31.31, 6332.91, 30.39, 14.99),
            vector4(28.1, 6331.0, 30.39, 17.32),
            vector4(24.33, 6329.44, 30.4, 17.65),
            vector4(21.04, 6327.19, 30.39, 16.33),
            vector4(17.8, 6325.34, 30.39, 18.4),
            vector4(14.34, 6323.88, 30.4, 14.39),
            vector4(10.86, 6321.81, 30.4, 14.85),
            vector4(7.62, 6319.48, 30.4, 16.6),
            vector4(-0.19, 6341.23, 30.39, 211.57),
            vector4(-2.89, 6338.23, 30.39, 211.86),
            vector4(-5.91, 6335.79, 30.39, 209.8),
            vector4(-8.95, 6333.29, 30.39, 212.65),
            vector4(-11.79, 6330.55, 30.39, 212.89),
            vector4(-14.36, 6327.86, 30.39, 209.62),
            vector4(-17.09, 6324.9, 30.39, 207.99),
            vector4(-19.89, 6322.32, 30.39, 209.87)
        },
        blip = {
            label = 'Public Parking',
            sprite = 357,
            colour = 3,
            scale = 0.7
        },
        classes = Config.VehicleClasses['car']
    },

    city_service_parking = {
        label = 'City Service Parking',
        bounds = {
             points = {
                vector3(-536.84, -270.7, 35.17),
                vector3(-535.41, -274.12, 35.15),
                vector3(-484.38, -253.99, 35.72),
                vector3(-486.22, -249.61, 35.88),
             },
             thickness = 10.0
        },
        spots = {
            vector4(-488.19, -252.74, 35.04, 113.39),
            vector4(-494.01, -255.06, 34.98, 111.66),
            vector4(-498.75, -256.95, 34.93, 111.68),
            vector4(-504.36, -259.16, 34.89, 111.48),
            vector4(-510.04, -261.41, 34.82, 112.85),
            vector4(-515.41, -263.65, 34.76, 112.5),
            vector4(-520.78, -265.88, 34.69, 112.58),
            vector4(-526.29, -268.17, 34.63, 112.57),
            vector4(-532.35, -270.69, 34.57, 112.57),
      },
        blip = false
    },
        st_fiacre_hospital_parking = {
        label = 'St Fiacre Hospital Parking',
        bounds = {
             points = {
                vector3(1160.27, -1464.89, 34.84),
                vector3(1160.39, -1485.69, 34.84),
                vector3(1154.01, -1485.49, 34.69),
                vector3(1154.18, -1465.08, 34.69),

             },
             thickness = 10.0
        },
        spots = {
            vector4(1157.5, -1467.05, 34.05, 89.98),
            vector4(1157.56, -1470.58, 34.05, 90.36),
            vector4(1157.24, -1474.24, 34.05, 90.92),
            vector4(1157.06, -1477.77, 34.05, 89.4),
      },
        blip = false
    },
    
    foundary_parking = {
        label = 'Foundary Parking',
        bounds = {
             points = {
                vector3(1016.89, -1970.39, 31.11),
                vector3(993.38, -1970.35, 30.69),
                vector3(972.42, -1956.07, 30.8),
                vector3(980.99, -1941.54, 31.09),
                vector3(1004.65, -1941.48, 31.11),
                vector3(1016.05, -1955.04, 31.12),
             },
             thickness = 10.0
        },
        spots = {
            vector4(1014.9, -1967.02, 30.46, 359.83),
            vector4(1011.72, -1967.06, 30.43, 359.71),
            vector4(1008.44, -1967.04, 30.36, 0.33),
            vector4(1005.3, -1967.07, 30.29, 1.39),
            vector4(1002.05, -1966.83, 30.21, 359.52),
            vector4(998.81, -1967.17, 30.15, 0.6),
            vector4(995.54, -1967.36, 30.09, 1.8),
            vector4(1007.38, -1956.04, 30.41, 0.51),
            vector4(1004.15, -1955.05, 30.33, 0.59),
            vector4(1001.01, -1955.09, 30.25, 0.7),
            vector4(997.8, -1955.13, 30.18, 1.61),
            vector4(994.65, -1954.98, 30.16, 359.64),
            vector4(991.45, -1955.5, 30.13, 0.17),
            vector4(988.21, -1955.81, 30.13, 1.05),
            vector4(1002.04, -1944.74, 30.42, 180.53),
            vector4(998.78, -1944.39, 30.4, 180.17),
            vector4(995.61, -1944.59, 30.38, 180.8),
            vector4(992.5, -1944.57, 30.37, 180.14),
            vector4(989.19, -1944.31, 30.37, 180.77),
            vector4(985.93, -1944.28, 30.37, 180.54),
            vector4(982.75, -1944.55, 30.37, 180.14),
      },
        blip = false
    },


    vinewood_parking = {
        label = 'Vinewood Parking',
        bounds = {
            points = {
                vector3(-352.92, 301.47, 84.76),
                vector3(-325.21, 309.92, 86.6),
                vector3(-325.29, 271.42, 86.56),
                vector3(-352.32, 268.84, 84.95),
            },
            thickness = 10.0
        },
        spots = {
            vector4(-328.72, 274.27, 85.59, 93.37),
            vector4(-329.25, 277.85, 85.55, 93.89),
            vector4(-329.06, 281.45, 85.5, 93.48),
            vector4(-329.25, 285.26, 85.39, 94.69),
            vector4(-329.37, 288.97, 85.37, 94.6),
            vector4(-329.13, 292.57, 85.39, 92.62),
            vector4(-328.89, 295.93, 85.4, 96.1),
            vector4(-328.99, 299.07, 85.4, 94.05),
            vector4(-329.15, 302.36, 85.39, 93.31),
            vector4(-329.35, 305.63, 85.39, 94.61),
            vector4(-339.52, 300.28, 84.75, 95.03),
            vector4(-339.92, 297.05, 84.72, 95.91),
            vector4(-340.18, 293.8, 84.7, 95.46),
            vector4(-340.1, 290.46, 84.7, 97.33),
            vector4(-340.38, 286.86, 84.68, 94.73),
            vector4(-339.89, 283.46, 84.71, 94.51),
            vector4(-339.73, 279.38, 84.79, 96.07),
            vector4(-349.52, 272.31, 84.33, 270.83),
            vector4(-349.34, 276.01, 84.26, 270.66),
            vector4(-349.67, 279.34, 84.17, 271.55),
            vector4(-349.42, 282.51, 84.17, 271.31),
            vector4(-349.52, 286.18, 84.17, 271.31),
            vector4(-349.2, 289.77, 84.19, 271.49),
            vector4(-349.38, 293.31, 84.18, 271.99),
            vector4(-349.74, 296.56, 84.16, 270.64)
        },
        blip = {
            label = 'Public Parking',
            sprite = 357,
            colour = 3,
            scale = 0.7
        },
        classes = Config.VehicleClasses['car']
    },

    bean_machine_parking = {
        label = 'Bean Machine Parking',
        bounds = {
            points = {
                vector3(-586.32, 203.33, 71.54),
                vector3(-586.16, 180.54, 71.07),
                vector3(-636.33, 180.57, 64.74),
                vector3(-636.81, 203.94, 71.16),
            },
            thickness = 10.0
        },
        spots = {
            vector4(-588.72, 181.95, 70.15, 87.74),
            vector4(-589.18, 185.04, 70.24, 91.22),
            vector4(-589.0, 188.1, 70.42, 88.79),
            vector4(-589.18, 191.45, 70.51, 90.55),
            vector4(-588.97, 194.27, 70.6, 89.66),
            vector4(-588.8, 197.36, 70.69, 89.57),
            vector4(-595.02, 200.72, 70.67, 179.7),
            vector4(-598.09, 200.92, 70.65, 179.15),
            vector4(-601.21, 200.96, 70.62, 180.43),
            vector4(-604.24, 200.89, 70.58, 179.47),
            vector4(-607.39, 201.02, 70.56, 179.34),
            vector4(-610.42, 200.98, 70.52, 179.55),
            vector4(-613.61, 200.8, 70.48, 179.89),
            vector4(-616.73, 200.82, 70.44, 179.51),
            vector4(-619.88, 200.78, 70.34, 180.73),
            vector4(-622.79, 200.61, 70.24, 179.66),
            vector4(-625.86, 200.69, 70.15, 179.22),
            vector4(-629.0, 200.42, 69.99, 180.11),
            vector4(-632.33, 200.62, 69.91, 180.52),
            vector4(-635.2, 200.63, 69.81, 179.74),
            vector4(-600.21, 189.83, 69.89, 160.22),
            vector4(-603.39, 190.21, 69.71, 161.97),
            vector4(-606.81, 189.84, 69.49, 161.35),
            vector4(-610.16, 190.08, 69.36, 157.55),
            vector4(-613.36, 190.18, 69.19, 159.93),
            vector4(-616.48, 189.91, 69.02, 159.54),
            vector4(-619.66, 189.98, 68.72, 160.72),
            vector4(-623.03, 189.59, 68.34, 161.22),
            vector4(-625.9, 189.87, 68.08, 158.64)
        },
        blip = {
            label = 'Public Parking',
            sprite = 357,
            colour = 3,
            scale = 0.7
        },
        classes = Config.VehicleClasses['car']
    },

    del_perro_pier_parking = {
        label = 'Del Perro Pier Parking',
        bounds = {
            points = {
                vector3(-1589.51, -824.88, 9.95),
                vector3(-1606.21, -856.35, 10.12),
                vector3(-1567.06, -890.73, 10.18),
                vector3(-1632.47, -972.34, 7.68),
                vector3(-1704.33, -947.53, 7.72),
                vector3(-1731.44, -909.4, 7.73),
                vector3(-1651.16, -817.18, 10.19),
                vector3(-1623.68, -796.14, 10.19)
            },
            thickness = 10.0
        },
        spots = {
            vector4(-1593.76, -825.99, 9.21, 138.87),
            vector4(-1595.97, -824.11, 9.21, 139.72),
            vector4(-1598.81, -822.53, 9.22, 139.98),
            vector4(-1601.33, -820.59, 9.22, 139.5),
            vector4(-1603.67, -818.62, 9.23, 140.7),
            vector4(-1606.0, -816.77, 9.25, 139.97),
            vector4(-1608.19, -814.53, 9.26, 140.03),
            vector4(-1610.64, -812.7, 9.28, 139.63),
            vector4(-1613.63, -811.5, 9.3, 141.67),
            vector4(-1615.43, -808.75, 9.31, 139.13),
            vector4(-1617.44, -806.27, 9.33, 140.29),
            vector4(-1620.05, -804.76, 9.35, 139.13),
            vector4(-1622.42, -802.65, 9.37, 139.4),
            vector4(-1624.43, -800.32, 9.4, 138.78),
            vector4(-1642.97, -833.92, 9.25, 138.16),
            vector4(-1640.47, -835.99, 9.24, 138.45),
            vector4(-1638.31, -838.03, 9.24, 139.28),
            vector4(-1635.79, -839.9, 9.23, 138.39),
            vector4(-1633.25, -841.89, 9.24, 139.01),
            vector4(-1631.08, -843.79, 9.26, 138.58),
            vector4(-1628.79, -845.87, 9.27, 139.17),
            vector4(-1626.44, -847.92, 9.26, 138.88),
            vector4(-1624.15, -849.75, 9.26, 139.45),
            vector4(-1621.83, -851.93, 9.27, 139.99),
            vector4(-1619.6, -854.16, 9.26, 138.87),
            vector4(-1617.4, -856.42, 9.24, 138.59),
            vector4(-1607.76, -864.0, 9.25, 138.8),
            vector4(-1605.45, -865.99, 9.26, 138.65),
            vector4(-1602.8, -867.79, 9.25, 139.4),
            vector4(-1581.19, -903.21, 8.88, 318.37),
            vector4(-1583.51, -901.11, 8.88, 319.25),
            vector4(-1585.8, -898.97, 8.88, 320.31),
            vector4(-1588.46, -897.26, 8.86, 320.28),
            vector4(-1590.9, -895.43, 8.8, 319.65),
            vector4(-1602.3, -886.11, 8.83, 318.04),
            vector4(-1604.66, -884.15, 8.79, 319.81),
            vector4(-1607.13, -882.15, 8.78, 318.0),
            vector4(-1609.35, -880.05, 8.82, 319.75),
            vector4(-1611.64, -878.02, 8.84, 319.27),
            vector4(-1614.04, -876.18, 8.84, 319.34),
            vector4(-1616.68, -874.21, 8.83, 319.14),
            vector4(-1618.59, -871.97, 8.84, 319.69),
            vector4(-1621.12, -870.18, 8.83, 318.84),
            vector4(-1623.39, -868.1, 8.84, 318.63),
            vector4(-1625.75, -866.14, 8.84, 318.13),
            vector4(-1627.93, -863.97, 8.85, 318.73),
            vector4(-1630.56, -862.14, 8.84, 319.84),
            vector4(-1636.42, -857.01, 8.83, 318.79),
            vector4(-1638.82, -855.13, 8.82, 318.55),
            vector4(-1641.09, -852.95, 8.81, 320.01),
            vector4(-1643.5, -851.17, 8.78, 318.53),
            vector4(-1645.78, -848.86, 8.76, 319.82),
            vector4(-1648.1, -846.85, 8.74, 319.19),
            vector4(-1650.58, -845.0, 8.74, 319.67),
            vector4(-1653.1, -843.42, 8.77, 318.45),
            vector4(-1655.3, -841.09, 8.82, 319.73),
            vector4(-1657.59, -839.27, 8.81, 318.95),
            vector4(-1659.76, -836.9, 8.83, 318.63),
            vector4(-1662.3, -835.17, 8.81, 319.41),
            vector4(-1666.52, -839.95, 8.64, 138.37),
            vector4(-1663.96, -841.76, 8.65, 139.45),
            vector4(-1661.83, -844.01, 8.64, 138.13),
            vector4(-1659.6, -846.1, 8.62, 139.5),
            vector4(-1657.04, -847.89, 8.59, 138.39),
            vector4(-1654.63, -849.66, 8.57, 138.17),
            vector4(-1652.37, -851.87, 8.58, 139.59),
            vector4(-1650.09, -853.93, 8.61, 139.69),
            vector4(-1647.66, -855.77, 8.64, 138.97),
            vector4(-1645.5, -858.02, 8.65, 139.16),
            vector4(-1642.84, -859.76, 8.66, 138.56),
            vector4(-1640.69, -861.88, 8.66, 138.66),
            vector4(-1638.18, -863.66, 8.67, 138.8),
            vector4(-1634.57, -866.93, 8.67, 138.56),
            vector4(-1632.33, -869.15, 8.66, 140.11),
            vector4(-1630.06, -871.01, 8.66, 139.68),
            vector4(-1627.61, -873.08, 8.66, 138.38),
            vector4(-1625.41, -875.12, 8.66, 139.21),
            vector4(-1623.02, -877.02, 8.66, 139.1),
            vector4(-1620.67, -879.03, 8.66, 139.41),
            vector4(-1618.18, -880.82, 8.66, 139.17),
            vector4(-1615.98, -883.22, 8.63, 139.45),
            vector4(-1613.53, -884.86, 8.62, 139.74),
            vector4(-1611.13, -886.79, 8.61, 139.27),
            vector4(-1608.97, -889.12, 8.6, 139.51),
            vector4(-1606.33, -890.76, 8.64, 138.67),
            vector4(-1594.94, -900.26, 8.63, 139.54),
            vector4(-1592.49, -902.1, 8.65, 139.1),
            vector4(-1590.29, -904.13, 8.66, 139.12),
            vector4(-1587.87, -906.06, 8.66, 138.94),
            vector4(-1585.4, -908.03, 8.67, 138.35),
            vector4(-1594.02, -918.17, 8.3, 319.23),
            vector4(-1596.43, -916.21, 8.3, 319.4),
            vector4(-1598.91, -914.37, 8.3, 320.05),
            vector4(-1601.37, -912.59, 8.29, 318.5),
            vector4(-1603.41, -910.28, 8.3, 319.9),
            vector4(-1615.16, -901.07, 8.29, 318.87),
            vector4(-1617.63, -899.27, 8.29, 317.92),
            vector4(-1619.78, -897.09, 8.29, 320.24),
            vector4(-1622.22, -895.12, 8.29, 319.32),
            vector4(-1624.43, -893.04, 8.29, 318.88),
            vector4(-1626.79, -891.11, 8.29, 318.45),
            vector4(-1629.1, -889.04, 8.29, 318.87),
            vector4(-1631.61, -887.26, 8.29, 319.41),
            vector4(-1633.88, -884.99, 8.29, 319.81),
            vector4(-1636.33, -883.19, 8.29, 319.28),
            vector4(-1638.63, -881.23, 8.29, 319.22),
            vector4(-1640.91, -879.23, 8.29, 318.59),
            vector4(-1643.4, -877.25, 8.28, 319.98),
            vector4(-1646.77, -874.03, 8.29, 317.29),
            vector4(-1649.3, -872.07, 8.29, 318.54),
            vector4(-1651.75, -870.24, 8.28, 319.23),
            vector4(-1653.88, -868.06, 8.29, 319.42),
            vector4(-1656.29, -865.98, 8.29, 319.34),
            vector4(-1658.75, -864.2, 8.28, 318.18),
            vector4(-1661.17, -862.2, 8.28, 319.14),
            vector4(-1663.45, -860.22, 8.28, 318.28),
            vector4(-1665.95, -858.22, 8.28, 318.24),
            vector4(-1668.0, -856.11, 8.29, 319.67),
            vector4(-1670.45, -854.19, 8.28, 318.72),
            vector4(-1672.79, -852.18, 8.28, 319.42),
            vector4(-1675.15, -850.29, 8.28, 319.73),
            vector4(-1679.41, -855.19, 8.22, 139.14),
            vector4(-1677.0, -857.02, 8.23, 139.59),
            vector4(-1674.58, -859.03, 8.23, 139.18),
            vector4(-1672.2, -860.86, 8.23, 139.23),
            vector4(-1670.03, -863.12, 8.23, 138.96),
            vector4(-1667.59, -865.07, 8.23, 139.45),
            vector4(-1665.36, -866.94, 8.23, 139.85),
            vector4(-1662.96, -869.12, 8.23, 139.74),
            vector4(-1660.57, -871.01, 8.23, 139.08),
            vector4(-1658.13, -872.96, 8.23, 139.38),
            vector4(-1655.65, -874.68, 8.24, 139.66),
            vector4(-1653.53, -876.89, 8.23, 138.94),
            vector4(-1651.0, -878.79, 8.24, 139.32),
            vector4(-1647.58, -882.11, 8.23, 138.66),
            vector4(-1645.15, -883.98, 8.23, 139.05),
            vector4(-1642.92, -886.18, 8.23, 139.52),
            vector4(-1640.4, -888.01, 8.23, 139.49),
            vector4(-1638.05, -889.76, 8.24, 139.83),
            vector4(-1636.0, -892.21, 8.23, 139.87),
            vector4(-1633.39, -894.1, 8.23, 139.62),
            vector4(-1631.27, -896.2, 8.23, 139.18),
            vector4(-1628.91, -898.12, 8.23, 138.27),
            vector4(-1626.54, -900.13, 8.23, 139.55),
            vector4(-1623.78, -901.73, 8.24, 139.2),
            vector4(-1621.61, -903.81, 8.24, 139.95),
            vector4(-1619.14, -905.75, 8.24, 139.76),
            vector4(-1607.61, -915.1, 8.25, 137.73),
            vector4(-1603.23, -919.21, 8.24, 138.65),
            vector4(-1600.49, -921.0, 8.25, 139.09),
            vector4(-1598.74, -923.33, 8.24, 137.66),
            vector4(-1606.98, -933.21, 8.02, 319.45),
            vector4(-1609.48, -931.41, 8.01, 318.83),
            vector4(-1611.71, -929.23, 8.01, 318.85),
            vector4(-1613.87, -927.17, 8.02, 319.26),
            vector4(-1616.21, -925.09, 8.02, 320.36),
            vector4(-1627.83, -915.97, 8.01, 320.27),
            vector4(-1630.34, -914.19, 8.0, 319.84),
            vector4(-1632.71, -912.14, 8.0, 318.97),
            vector4(-1634.98, -910.25, 8.0, 318.63),
            vector4(-1637.38, -908.24, 8.0, 318.65),
            vector4(-1639.83, -906.3, 8.0, 319.27),
            vector4(-1641.96, -904.1, 8.0, 319.07),
            vector4(-1644.41, -902.35, 8.0, 319.85),
            vector4(-1646.78, -900.19, 8.0, 319.22),
            vector4(-1649.08, -898.23, 8.0, 318.54),
            vector4(-1651.32, -896.06, 8.0, 319.16),
            vector4(-1653.73, -894.15, 8.0, 319.25),
            vector4(-1656.05, -892.22, 8.0, 318.96),
            vector4(-1659.84, -889.02, 8.0, 320.49),
            vector4(-1662.22, -887.32, 7.99, 318.92),
            vector4(-1664.6, -885.36, 7.99, 319.49),
            vector4(-1666.86, -883.15, 7.99, 319.18),
            vector4(-1669.02, -881.18, 8.0, 320.31),
            vector4(-1671.61, -879.09, 7.99, 319.9),
            vector4(-1673.96, -877.48, 7.99, 318.95),
            vector4(-1675.95, -875.01, 8.0, 319.38),
            vector4(-1678.37, -872.98, 8.0, 319.87),
            vector4(-1680.88, -871.2, 7.99, 319.96),
            vector4(-1683.06, -868.98, 8.0, 319.47),
            vector4(-1685.47, -867.06, 7.99, 319.51),
            vector4(-1687.98, -865.22, 7.99, 319.91),
            vector4(-1692.38, -870.32, 7.86, 138.66),
            vector4(-1689.79, -872.0, 7.87, 140.17),
            vector4(-1687.48, -874.18, 7.86, 139.94),
            vector4(-1684.95, -875.79, 7.87, 138.56),
            vector4(-1682.66, -877.9, 7.87, 139.27),
            vector4(-1680.4, -879.93, 7.87, 138.66),
            vector4(-1677.77, -881.7, 7.88, 137.91),
            vector4(-1675.94, -884.41, 7.86, 140.48),
            vector4(-1673.43, -886.11, 7.87, 138.84),
            vector4(-1670.83, -887.95, 7.87, 138.68),
            vector4(-1668.53, -889.72, 7.87, 139.54),
            vector4(-1666.17, -891.87, 7.87, 140.22),
            vector4(-1663.99, -893.91, 7.87, 138.44),
            vector4(-1660.24, -897.09, 7.87, 139.29),
            vector4(-1657.95, -898.84, 7.87, 139.46),
            vector4(-1655.51, -901.05, 7.87, 139.21),
            vector4(-1653.21, -902.95, 7.87, 139.22),
            vector4(-1650.66, -904.65, 7.88, 140.01),
            vector4(-1648.64, -907.06, 7.87, 138.64),
            vector4(-1646.47, -909.25, 7.87, 139.61),
            vector4(-1643.86, -910.96, 7.88, 140.55),
            vector4(-1641.75, -913.41, 7.87, 140.15),
            vector4(-1639.19, -915.08, 7.88, 138.62),
            vector4(-1636.91, -917.0, 7.88, 140.03),
            vector4(-1634.47, -919.0, 7.88, 139.35),
            vector4(-1632.28, -921.02, 7.88, 139.51),
            vector4(-1620.62, -930.35, 7.88, 137.96),
            vector4(-1618.16, -931.99, 7.89, 140.03),
            vector4(-1615.83, -934.1, 7.89, 139.45),
            vector4(-1613.42, -935.95, 7.89, 139.46),
            vector4(-1611.3, -938.33, 7.89, 139.8),
            vector4(-1619.73, -948.34, 7.67, 318.74),
            vector4(-1621.86, -946.09, 7.67, 319.72),
            vector4(-1624.35, -944.14, 7.71, 320.11),
            vector4(-1626.97, -942.47, 7.85, 319.78),
            vector4(-1629.19, -940.39, 7.97, 320.07),
            vector4(-1640.64, -931.02, 7.97, 319.26),
            vector4(-1643.07, -929.18, 7.96, 318.54),
            vector4(-1645.47, -927.24, 7.96, 319.79),
            vector4(-1647.87, -925.02, 7.96, 319.73),
            vector4(-1650.03, -923.07, 7.96, 318.75),
            vector4(-1652.48, -921.15, 7.95, 320.07),
            vector4(-1654.96, -919.27, 7.94, 319.97),
            vector4(-1657.2, -917.21, 7.95, 319.84),
            vector4(-1659.52, -915.18, 7.95, 319.46),
            vector4(-1661.85, -913.22, 7.95, 319.68),
            vector4(-1664.01, -911.02, 7.95, 318.97),
            vector4(-1666.6, -909.21, 7.94, 320.15),
            vector4(-1668.78, -907.18, 7.94, 319.34),
            vector4(-1672.54, -903.95, 7.94, 319.99),
            vector4(-1674.73, -901.94, 7.95, 319.74),
            vector4(-1677.01, -899.95, 7.96, 319.68),
            vector4(-1679.44, -898.03, 7.95, 319.22),
            vector4(-1681.76, -895.88, 7.96, 319.81),
            vector4(-1684.0, -893.96, 7.95, 319.46),
            vector4(-1686.62, -892.09, 7.95, 319.01),
            vector4(-1688.86, -890.06, 7.95, 319.15),
            vector4(-1691.24, -888.17, 7.95, 319.1),
            vector4(-1693.64, -886.15, 7.95, 319.43),
            vector4(-1696.0, -884.1, 7.95, 319.27),
            vector4(-1698.25, -882.05, 7.95, 319.78),
            vector4(-1700.62, -880.11, 7.95, 319.64),
            vector4(-1704.8, -884.93, 7.81, 138.63),
            vector4(-1702.64, -887.15, 7.8, 139.26),
            vector4(-1700.37, -889.2, 7.79, 139.32),
            vector4(-1697.86, -891.03, 7.8, 139.69),
            vector4(-1695.46, -892.98, 7.81, 139.3),
            vector4(-1693.23, -895.21, 7.8, 139.37),
            vector4(-1690.85, -897.11, 7.8, 139.52),
            vector4(-1688.59, -899.1, 7.8, 139.65),
            vector4(-1686.03, -900.92, 7.81, 139.47),
            vector4(-1683.75, -902.97, 7.81, 139.36),
            vector4(-1681.52, -905.11, 7.8, 139.68),
            vector4(-1679.18, -907.12, 7.8, 139.39),
            vector4(-1676.75, -909.09, 7.81, 140.2),
            vector4(-1673.12, -912.17, 7.81, 139.36),
            vector4(-1670.79, -914.16, 7.81, 139.01),
            vector4(-1668.54, -916.16, 7.81, 139.5),
            vector4(-1666.06, -918.12, 7.81, 139.57),
            vector4(-1663.78, -920.13, 7.81, 140.15),
            vector4(-1661.46, -922.34, 7.81, 139.22),
            vector4(-1659.18, -924.31, 7.81, 139.47),
            vector4(-1656.86, -926.36, 7.81, 139.9),
            vector4(-1654.68, -928.56, 7.8, 139.79),
            vector4(-1652.26, -930.31, 7.81, 139.39),
            vector4(-1649.76, -932.19, 7.81, 139.62),
            vector4(-1647.51, -934.16, 7.82, 139.27),
            vector4(-1645.15, -936.29, 7.82, 139.0),
            vector4(-1633.43, -945.26, 7.82, 139.11),
            vector4(-1631.06, -947.24, 7.78, 140.28),
            vector4(-1628.85, -949.38, 7.77, 139.37),
            vector4(-1626.54, -951.42, 7.78, 139.33),
            vector4(-1624.3, -953.59, 7.78, 140.03),
            vector4(-1630.06, -965.18, 7.5, 319.17),
            vector4(-1632.52, -963.42, 7.5, 319.27),
            vector4(-1637.24, -959.35, 7.26, 319.58),
            vector4(-1635.01, -961.57, 7.25, 319.09),
            vector4(-1639.76, -957.47, 7.26, 319.74),
            vector4(-1641.99, -955.36, 7.26, 319.25),
            vector4(-1670.07, -932.37, 7.2, 319.48),
            vector4(-1672.45, -930.31, 7.2, 319.64),
            vector4(-1674.65, -928.15, 7.2, 319.17),
            vector4(-1677.11, -926.54, 7.19, 318.23),
            vector4(-1679.73, -924.66, 7.18, 319.33),
            vector4(-1681.82, -922.5, 7.19, 319.88),
            vector4(-1685.58, -919.39, 7.19, 319.14),
            vector4(-1687.89, -917.43, 7.19, 319.03),
            vector4(-1690.24, -915.4, 7.19, 318.86),
            vector4(-1692.49, -913.15, 7.2, 319.94),
            vector4(-1694.74, -911.07, 7.2, 319.55),
            vector4(-1697.26, -909.29, 7.19, 318.73),
            vector4(-1699.53, -907.33, 7.19, 319.7),
            vector4(-1701.87, -905.22, 7.19, 318.45),
            vector4(-1704.25, -903.29, 7.19, 318.89),
            vector4(-1706.46, -901.22, 7.2, 318.55),
            vector4(-1708.93, -899.32, 7.2, 318.9),
            vector4(-1711.24, -897.36, 7.2, 319.33),
            vector4(-1713.47, -895.12, 7.21, 319.23),
            vector4(-1717.55, -899.92, 7.08, 139.05),
            vector4(-1715.17, -901.86, 7.09, 138.84),
            vector4(-1712.82, -903.79, 7.09, 138.61),
            vector4(-1710.5, -905.93, 7.08, 139.12),
            vector4(-1708.1, -907.82, 7.08, 138.99),
            vector4(-1705.91, -909.92, 7.08, 139.38),
            vector4(-1703.41, -911.75, 7.08, 139.31),
            vector4(-1701.12, -913.87, 7.08, 138.91),
            vector4(-1698.85, -915.84, 7.08, 139.01),
            vector4(-1696.37, -917.77, 7.08, 139.47),
            vector4(-1694.13, -919.92, 7.08, 139.24),
            vector4(-1691.81, -921.99, 7.08, 140.0),
            vector4(-1689.52, -924.05, 7.09, 139.42),
            vector4(-1685.81, -927.04, 7.09, 139.05),
            vector4(-1683.53, -928.97, 7.09, 138.66),
            vector4(-1681.07, -931.12, 7.09, 139.88),
            vector4(-1676.58, -933.09, 7.09, 229.42),
            vector4(-1667.9, -952.7, 7.06, 342.8),
            vector4(-1670.8, -951.94, 7.06, 342.41),
            vector4(-1673.77, -950.97, 7.06, 343.32),
            vector4(-1676.64, -949.99, 7.06, 343.18),
            vector4(-1679.47, -948.89, 7.06, 343.7),
            vector4(-1682.53, -948.22, 7.06, 342.16),
            vector4(-1685.46, -947.32, 7.06, 343.45),
            vector4(-1688.42, -946.39, 7.06, 343.49),
            vector4(-1691.33, -945.46, 7.06, 343.16),
            vector4(-1694.26, -944.75, 7.06, 343.35),
            vector4(-1702.59, -936.19, 7.06, 292.54),
            vector4(-1703.87, -933.14, 7.05, 294.6),
            vector4(-1705.26, -930.54, 7.06, 294.37),
            vector4(-1706.58, -927.56, 7.06, 296.35),
            vector4(-1708.16, -924.81, 7.06, 299.06),
            vector4(-1709.85, -921.93, 7.06, 303.58)
        },
        blip = {
            label = 'Public Parking',
            sprite = 357,
            colour = 3,
            scale = 0.7
        },
        classes = Config.VehicleClasses['car']
    },

    -- --- The impound -------------------------------------------------------
    --
    -- Not a parking lot: you cannot leave a car here, and what you can take out
    -- is whatever the police have impounded, once you have paid the fee they
    -- set. Cars arrive here by police action, never by parking.
    --
    -- Coordinates are qb-garages' own `depotLot`, deliberately: it is where
    -- players already know to go, and taking the impound over rather than
    -- moving it means nobody has to be told anything.
    --
    -- Impounding itself is qb-policejob's, not ours. It writes `depotprice`
    -- straight onto `player_vehicles` -- this lot is only the counter you pay
    -- at, which is why it keeps working with qb-garages gone.

    impound = {
        label = 'Impound Lot',
        impound = true,

        bounds = {
            center = vector3(671.38, 233.19, 94.20),
            size = vector3(60.0, 50.0, 12.0),
            rotation = 0.0
        },

        spots = {
            vector4(680.63, 233.16, 93.23, 240.44),
            vector4(683.24, 236.35, 93.23, 240.44),
            vector4(685.86, 239.55, 93.23, 240.44),
            vector4(678.02, 229.97, 93.23, 240.44),
            vector4(675.41, 226.78, 93.23, 240.44)
        },

        blip = {
            label = 'Impound Lot',
            sprite = 68,
            colour = 5,
            scale = 0.8
        },

        classes = Config.VehicleClasses['all']
    },
}
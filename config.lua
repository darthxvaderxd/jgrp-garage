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
}

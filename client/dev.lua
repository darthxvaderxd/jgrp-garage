--[[
    Config.Debug tooling. None of this registers unless Config.Debug is true.

    What it draws, for every lot within range:
      * the lot bounds, as a wireframe -- floor outline, ceiling outline, corner posts
      * every spot, green when free and red when a vehicle is sitting on it, using the
        same rule the server uses to decide where a retrieved car comes out
      * the lot id and label at the centre

    Building a lot:
      1. Walk the outline of the car park, running /parkbounds at each corner.
      2. Drive into each bay in turn, running /parkspot from the driver's seat.
         The order you capture them in is the order cars fall back through.
      3. /parkdump prints both arrays ready to paste into Config.Lots.
]]

if not Config.Debug then return end

local QBCore = exports['qb-core']:GetCoreObject()

local BOUNDS   = { r = 255, g = 176, b = 0 }
local FREE     = { r = 60,  g = 200, b = 90 }
local TAKEN    = { r = 220, g = 70,  b = 70 }
local DRAW_FROM = 60.0   -- how far outside a lot's radius the debug view kicks in
local LABEL_FROM = 20.0  -- how close you have to be for per-spot text

local bounds = {}
local spots = {}

local function drawText3D(coords, text)
    SetTextScale(0.34, 0.34)
    SetTextFont(4)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

--- Same rule the server applies in getOccupiedSpots, so what you see here is what
--- PickSpot would decide.
local function occupiedSpots(lot)
    local occupied = {}
    local vehicles = GetGamePool('CVehicle')
    local radius = Config.SpotOccupiedRadius

    for i = 1, #vehicles do
        local coords = GetEntityCoords(vehicles[i])

        for index = 1, #lot.spots do
            if not occupied[index] then
                local spot = lot.spots[index]

                if #(coords - vec3(spot.x, spot.y, spot.z)) <= radius then
                    occupied[index] = true
                end
            end
        end
    end

    return occupied
end

--- Wireframe rather than ox_lib's filled zone debug -- a solid box over a car park
--- hides the spots inside it.
local function drawBounds(lot)
    local count = #lot.polygon

    for i = 1, count do
        local a = lot.polygon[i]
        local b = lot.polygon[i % count + 1]

        DrawLine(a.x, a.y, lot.minZ, b.x, b.y, lot.minZ, BOUNDS.r, BOUNDS.g, BOUNDS.b, 225)
        DrawLine(a.x, a.y, lot.maxZ, b.x, b.y, lot.maxZ, BOUNDS.r, BOUNDS.g, BOUNDS.b, 110)
        DrawLine(a.x, a.y, lot.minZ, a.x, a.y, lot.maxZ, BOUNDS.r, BOUNDS.g, BOUNDS.b, 160)
    end
end

CreateThread(function()
    while true do
        local sleep = 1000
        local coords = GetEntityCoords(PlayerPedId())

        for _, lot in pairs(JGRPGarage.Lots) do
            if #(coords - lot.centre) < lot.radius + DRAW_FROM then
                sleep = 0

                drawBounds(lot)
                drawText3D(vec3(lot.centre.x, lot.centre.y, lot.minZ + 1.5),
                    ('%s  (%s)  %d spots'):format(lot.label, lot.id, #lot.spots))

                local occupied = occupiedSpots(lot)

                for index = 1, #lot.spots do
                    local spot = lot.spots[index]
                    local colour = occupied[index] and TAKEN or FREE

                    DrawMarker(1, spot.x, spot.y, spot.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        2.2, 2.2, 0.4, colour.r, colour.g, colour.b, 90,
                        false, false, 2, false, nil, nil, false)

                    if #(coords - vec3(spot.x, spot.y, spot.z)) < LABEL_FROM then
                        drawText3D(vec3(spot.x, spot.y, spot.z + 0.9),
                            ('spot %d%s'):format(index, occupied[index] and '  (taken)' or ''))
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

-- A one-off summary, so "why is there no blip" is answerable from the console.
CreateThread(function()
    Wait(500)

    local count = 0

    for _ in pairs(JGRPGarage.Lots) do count = count + 1 end

    print(('^2[jgrp-garage]^7 debug on, %d lot(s) loaded'):format(count))

    for id, lot in pairs(JGRPGarage.Lots) do
        print(('  ^5%s^7  "%s"  %d spots  %d bounds points  z %.1f..%.1f  blip: %s'):format(
            id, lot.label, #lot.spots, #lot.polygon, lot.minZ, lot.maxZ,
            lot.blip and 'yes' or 'no'))
    end
end)

RegisterCommand('parkspot', function()
    local ped = PlayerPedId()
    local entity = GetVehiclePedIsIn(ped, false)

    if entity == 0 then entity = ped end

    local coords = GetEntityCoords(entity)
    local heading = GetEntityHeading(entity)

    spots[#spots + 1] = ('            vec4(%.2f, %.2f, %.2f, %.2f)'):format(
        coords.x, coords.y, coords.z, heading)

    print(('^2[jgrp-garage]^7 spot %d captured'):format(#spots))
    QBCore.Functions.Notify(('Spot %d captured'):format(#spots), 'success')
end, false)

RegisterCommand('parkbounds', function()
    local coords = GetEntityCoords(PlayerPedId())

    bounds[#bounds + 1] = ('                vec3(%.2f, %.2f, %.2f)'):format(
        coords.x, coords.y, coords.z)

    print(('^2[jgrp-garage]^7 bounds point %d captured'):format(#bounds))
    QBCore.Functions.Notify(('Bounds point %d captured'):format(#bounds), 'success')
end, false)

RegisterCommand('parkclear', function()
    bounds, spots = {}, {}
    QBCore.Functions.Notify('Capture cleared', 'primary')
end, false)

RegisterCommand('parkdump', function()
    if #bounds == 0 and #spots == 0 then
        return QBCore.Functions.Notify('Nothing captured yet', 'error')
    end

    local out = {
        '',
        '    newlot = {',
        "        label = 'New Parking',",
        '        bounds = {',
        '            points = {'
    }

    for i = 1, #bounds do
        out[#out + 1] = bounds[i] .. (i < #bounds and ',' or '')
    end

    out[#out + 1] = '            },'
    out[#out + 1] = '            thickness = 10.0'
    out[#out + 1] = '        },'
    out[#out + 1] = '        spots = {'

    for i = 1, #spots do
        out[#out + 1] = spots[i] .. (i < #spots and ',' or '')
    end

    out[#out + 1] = '        },'
    out[#out + 1] = '        blip = false,'
    out[#out + 1] = "        classes = Config.VehicleClasses['car']"
    out[#out + 1] = '    },'
    out[#out + 1] = ''

    print(table.concat(out, '\n'))
    QBCore.Functions.Notify('Dumped to the F8 console', 'success')
end, false)

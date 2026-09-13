local QBCore = exports['qb-core']:GetCoreObject()

local PARK_OPTION = 'jgrp_garage_park'
local LIST_OPTION = 'jgrp_garage_list'

local currentLot    -- lot table we are stood in, or nil
local currentSpot   -- index of the spot our vehicle is sitting in, or nil
local parkShown, listShown = false, false
local busy = false

local function notify(message, type)
    QBCore.Functions.Notify(message, type or 'primary')
end

-- ---------------------------------------------------------------------------
-- Radial menu
-- ---------------------------------------------------------------------------

local function hasRadial()
    return GetResourceState('qb-radialmenu') == 'started'
end

local function showPark(show)
    if show == parkShown or not hasRadial() then
        parkShown = show
        return
    end

    if show then
        exports['qb-radialmenu']:AddOption({
            id = PARK_OPTION,
            title = Config.ParkTitle,
            icon = Config.ParkIcon,
            type = 'client',
            event = 'jgrp-garage:client:park',
            shouldClose = true
        }, PARK_OPTION)
    else
        exports['qb-radialmenu']:RemoveOption(PARK_OPTION)
    end

    parkShown = show
end

local function showList(show)
    if show == listShown or not hasRadial() then
        listShown = show
        return
    end

    if show then
        exports['qb-radialmenu']:AddOption({
            id = LIST_OPTION,
            title = Config.ListTitle,
            icon = Config.ListIcon,
            type = 'client',
            event = 'jgrp-garage:client:openLot',
            shouldClose = true
        }, LIST_OPTION)
    else
        exports['qb-radialmenu']:RemoveOption(LIST_OPTION)
    end

    listShown = show
end

local function clearOptions()
    showPark(false)
    showList(false)
    currentSpot = nil
end

-- ---------------------------------------------------------------------------
-- Lot presence
-- ---------------------------------------------------------------------------

--- Bumped every time we enter a lot, so that where two lots overlap only the
--- thread for the one we entered most recently is left driving the options.
local generation = 0

--- Runs only while stood inside a lot. Decides which of the two radial options
--- should be up: "Park Vehicle" when driving a car that is sitting in a spot,
--- "Parking Lot" otherwise.
local function watchLot(lot, mine)
    CreateThread(function()
        while currentLot == lot and generation == mine do
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
                showList(false)
                currentSpot = JGRPGarage.GetSpotAt(lot, GetEntityCoords(vehicle))
                showPark(currentSpot ~= nil)
            else
                showPark(false)
                currentSpot = nil
                showList(true)
            end

            Wait(Config.PollInterval)
        end

        if generation == mine then clearOptions() end
    end)
end

local function enterLot(lot)
    generation = generation + 1
    currentLot = lot
    watchLot(lot, generation)
end

local function exitLot(lot)
    if currentLot ~= lot then return end

    generation = generation + 1
    currentLot = nil
    clearOptions()
end

-- ---------------------------------------------------------------------------
-- Parking
-- ---------------------------------------------------------------------------

AddEventHandler('jgrp-garage:client:park', function()
    if busy then return end

    local lot, spotIndex = currentLot, currentSpot

    if not lot or not spotIndex then
        return notify('You are not in a parking spot.', 'error')
    end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then
        return notify('You have to be driving the vehicle to park it.', 'error')
    end

    if not JGRPGarage.IsClassAllowed(lot, GetVehicleClass(vehicle)) then
        return notify('This lot does not take that kind of vehicle.', 'error')
    end

    busy = true

    if Config.ParkDuration > 0 then
        local finished = lib.progressCircle({
            duration = Config.ParkDuration,
            label = 'Parking',
            position = 'bottom',
            canCancel = true,
            disable = { move = true, car = true, combat = true }
        })

        if not finished then
            busy = false
            return
        end

        -- The car may have rolled out of the spot while the bar ran.
        if not DoesEntityExist(vehicle) or JGRPGarage.GetSpotAt(lot, GetEntityCoords(vehicle)) ~= spotIndex then
            busy = false
            return notify('You are not in a parking spot.', 'error')
        end
    end

    local ok, message = lib.callback.await('jgrp-garage:server:park', false, {
        lotId = lot.id,
        spotIndex = spotIndex,
        netId = VehToNet(vehicle),
        plate = QBCore.Functions.GetPlate(vehicle),
        props = QBCore.Functions.GetVehicleProperties(vehicle),
        fuel = Config.GetFuel(vehicle),
        engine = GetVehicleEngineHealth(vehicle),
        body = GetVehicleBodyHealth(vehicle)
    })

    busy = false

    notify(message, ok and 'success' or 'error')

    if ok then clearOptions() end
end)

-- ---------------------------------------------------------------------------
-- Retrieving
-- ---------------------------------------------------------------------------

local function waitForVehicle(netId)
    local timeout = 0

    while not NetworkDoesNetworkIdExist(netId) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end

    if not NetworkDoesNetworkIdExist(netId) then return 0 end

    local vehicle = NetToVeh(netId)
    timeout = 0

    while not DoesEntityExist(vehicle) and timeout < 100 do
        Wait(10)
        vehicle = NetToVeh(netId)
        timeout = timeout + 1
    end

    return DoesEntityExist(vehicle) and vehicle or 0
end

local function retrieve(lotId, plate)
    if busy then return end

    busy = true

    local ok, result = lib.callback.await('jgrp-garage:server:retrieve', false, lotId, plate)

    if not ok then
        busy = false
        return notify(result, 'error')
    end

    local vehicle = waitForVehicle(result.netId)

    if vehicle == 0 then
        busy = false
        return notify('The vehicle did not load in. Try again.', 'error')
    end

    -- SetVehicleProperties only sticks on an entity we own.
    local timeout = 0

    while not NetworkHasControlOfEntity(vehicle) and timeout < 50 do
        NetworkRequestControlOfEntity(vehicle)
        Wait(10)
        timeout = timeout + 1
    end

    if result.props and next(result.props) then
        QBCore.Functions.SetVehicleProperties(vehicle, result.props)
    end

    SetVehicleNumberPlateText(vehicle, result.plate)
    Config.SetFuel(vehicle, result.fuel)
    Config.GiveKey(result.plate)
    SetVehicleEngineOn(vehicle, false, true, false)

    if Config.WarpIntoVehicle then
        TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
    end

    busy = false

    if result.wasPreferred then
        notify(('Your vehicle is waiting in spot %d.'):format(result.spotIndex), 'success')
    else
        notify(('Your spot was taken -- parked in spot %d instead.'):format(result.spotIndex), 'primary')
    end
end

local function conditionOf(value)
    return ('%d%%'):format(math.floor(math.max(0, math.min(1000, tonumber(value) or 1000)) / 10))
end

AddEventHandler('jgrp-garage:client:openLot', function()
    if busy then return end

    local lot = currentLot
    if not lot then return end

    local vehicles = lib.callback.await('jgrp-garage:server:getVehicles', false, lot.id)

    if not vehicles or #vehicles == 0 then
        return notify('You have nothing parked here.', 'error')
    end

    local options = {}

    for i = 1, #vehicles do
        local row = vehicles[i]
        local data = QBCore.Shared.Vehicles[row.vehicle]
        local name = data and ('%s %s'):format(data.brand, data.name) or row.vehicle
        local spot = tonumber(row.parkingspot)

        options[#options + 1] = {
            title = name,
            description = spot and ('Spot %d'):format(spot) or 'No spot recorded',
            icon = 'car',
            metadata = {
                { label = 'Plate',  value = row.plate },
                { label = 'Fuel',   value = ('%d%%'):format(math.floor(tonumber(row.fuel) or 100)) },
                { label = 'Engine', value = conditionOf(row.engine) },
                { label = 'Body',   value = conditionOf(row.body) }
            },
            onSelect = function()
                retrieve(lot.id, row.plate)
            end
        }
    end

    lib.registerContext({
        id = 'jgrp_garage_vehicles',
        title = lot.label,
        options = options
    })

    lib.showContext('jgrp_garage_vehicles')
end)

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------

local blips = {}

local function createBlips()
    for _, lot in pairs(JGRPGarage.Lots) do
        if lot.blip then
            local blip = AddBlipForCoord(lot.centre.x, lot.centre.y, lot.centre.z)

            SetBlipSprite(blip, lot.blip.sprite or 357)
            SetBlipColour(blip, lot.blip.colour or 3)
            SetBlipScale(blip, lot.blip.scale or 0.7)
            SetBlipDisplay(blip, 4)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(lot.blip.label or lot.label)
            EndTextCommandSetBlipName(blip)

            blips[#blips + 1] = blip
        end
    end
end

local function createZones()
    for _, lot in pairs(JGRPGarage.Lots) do
        local midZ = (lot.minZ + lot.maxZ) * 0.5
        local points = {}

        for i = 1, #lot.polygon do
            points[i] = vec3(lot.polygon[i].x, lot.polygon[i].y, midZ)
        end

        -- ox_lib's own zone debug fills the volume with solid polys, which hides
        -- the spots inside a car park. client/dev.lua draws a wireframe instead.
        lib.zones.poly({
            points = points,
            thickness = lot.maxZ - lot.minZ,
            onEnter = function() enterLot(lot) end,
            onExit = function() exitLot(lot) end
        })
    end
end

CreateThread(function()
    createZones()
    createBlips()

    if not hasRadial() then
        print('^3[jgrp-garage]^7 qb-radialmenu is not started -- use /park and /parking instead')
    end
end)

-- Fallbacks, and handy for testing without opening the radial.
RegisterCommand('park', function()
    TriggerEvent('jgrp-garage:client:park')
end, false)

RegisterCommand('parking', function()
    TriggerEvent('jgrp-garage:client:openLot')
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    currentLot = nil
    clearOptions()

    for i = 1, #blips do
        RemoveBlip(blips[i])
    end
end)

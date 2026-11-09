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

local function incapacitated()
    local md = QBCore.Functions.GetPlayerData().metadata or {}
    return (md.isdead or md.inlaststand or md.ishandcuffed or IsPedDeadOrDying(PlayerPedId(), true)) and true or false
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
            -- The pound lists what was towed, not what you parked, so it is
            -- not called the same thing.
            title = (currentLot and currentLot.impound) and Config.ImpoundTitle or Config.ListTitle,
            icon = (currentLot and currentLot.impound) and Config.ImpoundIcon or Config.ListIcon,
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
                currentSpot = not lot.impound and JGRPGarage.GetSpotAt(lot, GetEntityCoords(vehicle)) or nil
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
    if lot.job then
        local job = QBCore.Functions.GetPlayerData().job
        if not job or job.name ~= lot.job then return end
    end

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

local parkAsVan = {}
for _, name in ipairs(Config.ParkAsVan or {}) do parkAsVan[joaat(name)] = true end

AddEventHandler('jgrp-garage:client:park', function()
    if busy then return end

    if incapacitated() then
        return notify("You can't do that right now.", 'error')
    end

    local lot, spotIndex = currentLot, currentSpot

    if not lot or not spotIndex then
        return notify('You are not in a parking spot.', 'error')
    end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then
        return notify('You have to be driving the vehicle to park it.', 'error')
    end

    local class = GetVehicleClass(vehicle)
    if parkAsVan[GetEntityModel(vehicle)] then class = 12 end

    if not JGRPGarage.IsClassAllowed(lot, class) then
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

        if incapacitated() then
            busy = false
            return notify("You can't do that right now.", 'error')
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
        -- LOCAL FIX (interim, until qb-core restarts with its own fix): qb-core threw
        -- "invalid table argument" in SetVehicleColours when color1 is a custom {r,g,b}
        -- table and color2 is a number. Hold color2 back and apply it ourselves.
        local props = result.props
        local heldColor2
        if type(props.color1) == 'table' and type(props.color2) == 'number' then
            heldColor2 = props.color2
            props.color2 = nil
        end

        QBCore.Functions.SetVehicleProperties(vehicle, props)

        if heldColor2 then
            local primary = GetVehicleColours(vehicle)
            ClearVehicleCustomSecondaryColour(vehicle)
            SetVehicleColours(vehicle, primary, heldColor2)
            -- SetVehicleColours resets custom primary paint; reapply it.
            SetVehicleCustomPrimaryColour(vehicle, props.color1[1], props.color1[2], props.color1[3])
        end
    end

    SetVehicleNumberPlateText(vehicle, result.plate)
    Config.SetFuel(vehicle, result.fuel)
    Config.GiveKey(result.plate)
    SetVehicleEngineOn(vehicle, false, true, false)

    if Config.WarpIntoVehicle then
        TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
    end

    busy = false

    -- A released car has no remembered spot to have been given back, so the
    -- spot messages would be noise -- what matters is what it cost.
    if result.fee then
        notify(('Released for $%d.'):format(result.fee), 'success')
    elseif result.wasPreferred then
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

    if incapacitated() then
        return notify("You can't do that right now.", 'error')
    end

    local lot = currentLot
    if not lot then return end

    local vehicles = lib.callback.await('jgrp-garage:server:getVehicles', false, lot.id)

    if not vehicles or #vehicles == 0 then
        return notify(lot.impound
            and 'The impound is not holding anything of yours.'
            or 'You have nothing parked here.', 'error')
    end

    local options = {}

    for i = 1, #vehicles do
        local row = vehicles[i]
        local data = QBCore.Shared.Vehicles[row.vehicle]
        local name = data and ('%s %s'):format(data.brand, data.name) or row.vehicle
        local spot = tonumber(row.parkingspot)

        local fee = lot.impound and math.floor(tonumber(row.depotprice) or 0) or nil

        local metadata = {
            { label = 'Plate',  value = row.plate },
            { label = 'Fuel',   value = ('%d%%'):format(math.floor(tonumber(row.fuel) or 100)) },
            { label = 'Engine', value = conditionOf(row.engine) },
            { label = 'Body',   value = conditionOf(row.body) }
        }

        if fee then
            table.insert(metadata, 1, { label = 'Release fee', value = ('$%d'):format(fee) })
        end

        options[#options + 1] = {
            title = name,
            description = fee
                and ('$%d to release'):format(fee)
                or (spot and ('Spot %d'):format(spot) or 'No spot recorded'),
            icon = lot.impound and 'money-bill' or 'car',
            metadata = metadata,
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

local function createZone(lot)
    local midZ = (lot.minZ + lot.maxZ) * 0.5
    local points = {}

    for i = 1, #lot.polygon do
        points[i] = vec3(lot.polygon[i].x, lot.polygon[i].y, midZ)
    end

    -- ox_lib's own zone debug fills the volume with solid polys, which hides
    -- the spots inside a car park. client/dev.lua draws a wireframe instead.
    return lib.zones.poly({
        points = points,
        thickness = lot.maxZ - lot.minZ,
        onEnter = function() enterLot(lot) end,
        onExit = function() exitLot(lot) end
    })
end

local function createZones()
    for _, lot in pairs(JGRPGarage.Lots) do
        createZone(lot)
    end
end

-- ---------------------------------------------------------------------------
-- House garages
-- ---------------------------------------------------------------------------

local houseZones = {}   -- lot id -> { zone, sig, lot }
local syncing = false

local function removeHouseZone(id)
    local entry = houseZones[id]
    if not entry then return end

    exitLot(entry.lot)
    entry.zone:remove()
    JGRPGarage.Lots[id] = nil
    houseZones[id] = nil
end

local function clearHouseZones()
    for id in pairs(houseZones) do removeHouseZone(id) end
end

--- Ask the server which house garages we may use and make the zones match.
--- The server re-checks access on every park/retrieve, so this only decides what
--- the client draws.
local function syncHouseLots()
    if syncing then return end
    syncing = true

    local okCall, list = pcall(lib.callback.await, 'jgrp-garage:server:getHouseLots', false)
    if not okCall then list = nil end

    if type(list) == 'table' then
        local seen = {}

        for _, h in ipairs(list) do
            seen[h.id] = true

            local g = h.g or {}
            local sig = ('%s|%.2f|%.2f|%.2f|%.1f'):format(
                h.label or '', tonumber(g.x) or 0, tonumber(g.y) or 0, tonumber(g.z) or 0,
                tonumber(g.h) or tonumber(g.w) or 0)
            local current = houseZones[h.id]

            if not current or current.sig ~= sig then
                if current then removeHouseZone(h.id) end

                local raw = JGRPGarage.MakeHouseRaw(h.id, h.label, g, h.legacy)
                local lot = raw and JGRPGarage.BuildLot(h.id, raw)

                if lot then
                    JGRPGarage.Lots[h.id] = lot
                    houseZones[h.id] = { zone = createZone(lot), sig = sig, lot = lot }
                end
            end
        end

        for id in pairs(houseZones) do
            if not seen[id] then removeHouseZone(id) end
        end
    end

    syncing = false
end

local function loggedIn()
    local data = QBCore.Functions.GetPlayerData()
    return data and data.citizenid ~= nil
end

CreateThread(function()
    while true do
        if loggedIn() then syncHouseLots() end
        Wait(Config.HouseRefreshMs or 30000)
    end
end)

local function syncSoon()
    CreateThread(function()
        Wait(1500)
        if loggedIn() then syncHouseLots() end
    end)
end

-- Both housing scripts announce garage changes under qb-garages' old names.
RegisterNetEvent('qb-garages:client:addHouseGarage', syncSoon)
RegisterNetEvent('qb-garages:client:removeHouseGarage', syncSoon)
RegisterNetEvent('qb-garages:client:houseGarageConfig', syncSoon)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', syncSoon)
RegisterNetEvent('QBCore:Client:OnPlayerUnload', clearHouseZones)

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

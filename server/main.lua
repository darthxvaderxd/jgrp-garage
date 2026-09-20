local QBCore = exports['qb-core']:GetCoreObject()

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------

--- Spot memory lives in one extra column on player_vehicles, added on first start.
local function ensureSchema()
    local exists = MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'player_vehicles'
          AND COLUMN_NAME = 'parkingspot'
    ]])

    if exists and exists > 0 then return end

    MySQL.query.await('ALTER TABLE `player_vehicles` ADD COLUMN `parkingspot` INT NULL DEFAULT NULL')
    print('^2[jgrp-garage]^7 added `parkingspot` column to `player_vehicles`')
end

--- Tow in everything that was left out when the server went down.
---
--- Those cars have no entity any more and nobody parked them, so the choice is
--- between quietly marking them stored -- a free garage for anyone who logs off
--- in the street -- and impounding them. This is the second, which is what
--- qb-garages did.
---
--- A fee the police already set is left alone: `depotprice > 0` means this car
--- was impounded for a reason, and a restart should not make it cheaper or
--- dearer to get back.
local function impoundOnStart()
    local price = math.max(1, math.floor(Config.ImpoundOnStartPrice or 250))

    local affected = MySQL.update.await([[
        UPDATE player_vehicles
        SET depotprice = ?
        WHERE state = 0 AND (depotprice IS NULL OR depotprice <= 0)
    ]], { price })

    if affected and affected > 0 then
        print(('^2[jgrp-garage]^7 impounded %d vehicle(s) left out, $%d each'):format(affected, price))
    end
end

local function restoreOnStart()
    if not Config.RestoreOnStart then return end

    local ids = {}

    for id in pairs(JGRPGarage.Lots) do
        ids[#ids + 1] = id
    end

    if #ids == 0 then return end

    local placeholders = string.rep('?', #ids, ',')
    local affected = MySQL.update.await(
        ('UPDATE player_vehicles SET state = 1 WHERE state = 0 AND garage IN (%s)'):format(placeholders),
        ids
    )

    if affected and affected > 0 then
        print(('^2[jgrp-garage]^7 restored %d vehicle(s) to their lots'):format(affected))
    end
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    ensureSchema()

    -- Impounding wins over restoring: they disagree about the same rows, and a
    -- car cannot be both back in its lot and in the pound.
    if Config.ImpoundOnStart then
        impoundOnStart()
    else
        restoreOnStart()
    end
end)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function getPlayer(source)
    return QBCore.Functions.GetPlayer(source)
end

local function normalisePlate(plate)
    if type(plate) ~= 'string' then return nil end

    plate = plate:match('^%s*(.-)%s*$')

    return plate ~= '' and plate or nil
end

--- Every spot in `lot` that currently has a vehicle sitting on it.
--- Retrieval is the only caller, and the car being retrieved does not exist yet,
--- so plain proximity is enough -- nothing needs to be excluded by plate.
local function getOccupiedSpots(lot)
    local occupied = {}

    if not GetAllVehicles then
        -- Very old FXServer builds. Nothing is known to be occupied, so a retrieved
        -- car always goes to its remembered spot.
        return occupied
    end

    local vehicles = GetAllVehicles()
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

--- Where a retrieved vehicle should come out. The rule itself lives in
--- shared/lots.lua; this just supplies the current occupancy.
local function pickSpot(lot, remembered)
    return JGRPGarage.PickSpot(lot, remembered, getOccupiedSpots(lot))
end

local function getVehicleType(model)
    local data = QBCore.Shared.Vehicles[model]

    return data and data.type or 'automobile'
end

-- GetVehicleClass is client-only, so the per-lot `classes` restriction is checked
-- against qb-core's own category for the model instead of trusting the client.
local classOfCategory = {
    compacts = 0, sedans = 1, suvs = 2, coupes = 3, muscle = 4,
    sportsclassics = 5, sports = 6, super = 7, motorcycles = 8, offroad = 9,
    industrial = 10, utility = 11, vans = 12, cycles = 13, boats = 14,
    helicopters = 15, planes = 16, service = 17, emergency = 18, military = 19,
    commercial = 20, trains = 21, openwheel = 22
}

local function getVehicleClass(model)
    local data = QBCore.Shared.Vehicles[model]

    return data and classOfCategory[data.category] or nil
end

-- ---------------------------------------------------------------------------
-- Callbacks
-- ---------------------------------------------------------------------------

--- The caller's vehicles stored in this lot, for the context menu.
--- What the impound is holding for you.
---
--- Keyed on `depotprice`, not on `garage`: a car is impounded by the police
--- writing a fee onto it, wherever it was, so which garage it belonged to says
--- nothing about whether it is in the pound. That is qb-garages' own rule and
--- the reason this keeps working with qb-garages gone.
local function impoundedVehicles(citizenid)
    local rows = MySQL.query.await([[
        SELECT plate, vehicle, fuel, engine, body, depotprice, state
        FROM player_vehicles
        WHERE citizenid = ? AND depotprice > 0 AND state != 2
        ORDER BY depotprice
    ]], { citizenid })

    return rows or {}
end

lib.callback.register('jgrp-garage:server:getVehicles', function(source, lotId)
    local Player = getPlayer(source)
    if not Player then return {} end

    local lot = JGRPGarage.GetLot(lotId)
    if not lot then return {} end

    local coords = GetEntityCoords(GetPlayerPed(source))
    if not JGRPGarage.IsInsideLot(lot, coords, Config.RetrieveTolerance) then return {} end

    if lot.impound then
        return impoundedVehicles(Player.PlayerData.citizenid)
    end

    local rows = MySQL.query.await([[
        SELECT plate, vehicle, fuel, engine, body, parkingspot
        FROM player_vehicles
        WHERE citizenid = ? AND garage = ? AND state = 1
        ORDER BY parkingspot IS NULL, parkingspot
    ]], { Player.PlayerData.citizenid, lotId })

    return rows or {}
end)

--- Store the vehicle the caller is sitting in.
lib.callback.register('jgrp-garage:server:park', function(source, data)
    local Player = getPlayer(source)
    if not Player then return false, 'Not loaded' end

    if type(data) ~= 'table' then return false, 'Bad request' end

    local lot = JGRPGarage.GetLot(data.lotId)
    if not lot then return false, 'Unknown parking lot' end

    -- The pound is somewhere cars are put, not somewhere you put them.
    if lot.impound then return false, 'You cannot leave a car at the impound' end

    local spotIndex = tonumber(data.spotIndex)
    if not spotIndex or not lot.spots[spotIndex] then return false, 'Not in a parking spot' end

    local plate = normalisePlate(data.plate)
    if not plate then return false, 'Bad plate' end

    local entity = NetworkGetEntityFromNetworkId(data.netId or 0)
    if entity == 0 or not DoesEntityExist(entity) then return false, 'Vehicle not found' end

    -- The vehicle really has to be sitting on the spot the client named.
    local spot = lot.spots[spotIndex]
    local distance = #(GetEntityCoords(entity) - vec3(spot.x, spot.y, spot.z))

    if distance > Config.SpotRadius + Config.ParkTolerance then
        return false, 'Not in a parking spot'
    end

    -- ...and the caller really has to be driving it.
    local occupant = GetVehiclePedIsIn(GetPlayerPed(source))

    if occupant ~= 0 and occupant ~= entity then
        return false, 'You are not driving that vehicle'
    end

    local row = MySQL.single.await(
        'SELECT plate, vehicle, state FROM player_vehicles WHERE plate = ? AND citizenid = ?',
        { plate, Player.PlayerData.citizenid }
    )

    if not row then return false, 'That vehicle is not yours' end
    if row.state == 1 then return false, 'That vehicle is already stored' end

    if not JGRPGarage.IsClassAllowed(lot, getVehicleClass(row.vehicle)) then
        return false, 'This lot does not take that kind of vehicle'
    end

    MySQL.update.await([[
        UPDATE player_vehicles
        SET state = 1, garage = ?, parkingspot = ?, fuel = ?, engine = ?, body = ?, mods = ?, depotprice = 0
        WHERE plate = ? AND citizenid = ?
    ]], {
        lot.id,
        spotIndex,
        math.floor(tonumber(data.fuel) or 100),
        tonumber(data.engine) or 1000.0,
        tonumber(data.body) or 1000.0,
        json.encode(data.props or {}),
        plate,
        Player.PlayerData.citizenid
    })

    DeleteEntity(entity)

    return true, ('Stored in spot %d'):format(spotIndex)
end)

--- Pull a stored vehicle back out.
lib.callback.register('jgrp-garage:server:retrieve', function(source, lotId, plate)
    local Player = getPlayer(source)
    if not Player then return false, 'Not loaded' end

    local lot = JGRPGarage.GetLot(lotId)
    if not lot then return false, 'Unknown parking lot' end

    plate = normalisePlate(plate)
    if not plate then return false, 'Bad plate' end

    local coords = GetEntityCoords(GetPlayerPed(source))
    if not JGRPGarage.IsInsideLot(lot, coords, Config.RetrieveTolerance) then
        return false, 'You are not in this parking lot'
    end

    local row, fee

    if lot.impound then
        row = MySQL.single.await([[
            SELECT plate, vehicle, mods, fuel, engine, body, depotprice
            FROM player_vehicles
            WHERE plate = ? AND citizenid = ? AND depotprice > 0 AND state != 2
        ]], { plate, Player.PlayerData.citizenid })

        if not row then return false, 'The impound is not holding that vehicle' end

        fee = math.floor(tonumber(row.depotprice) or 0)
        if fee < 1 then fee = Config.ImpoundFallbackPrice or 500 end

        -- Cash first, then the bank, which is the order qb-garages used and the
        -- one players expect. Taken before the car is spawned: a spawn that
        -- fails after payment would be a fee for nothing.
        local paid = false

        if Player.PlayerData.money.cash >= fee then
            paid = Player.Functions.RemoveMoney('cash', fee, 'jgrp-garage:impound')
        elseif Player.PlayerData.money.bank >= fee then
            paid = Player.Functions.RemoveMoney('bank', fee, 'jgrp-garage:impound')
        end

        if not paid then
            return false, ('You cannot afford the $%d release fee'):format(fee)
        end
    else
        row = MySQL.single.await([[
            SELECT plate, vehicle, mods, fuel, engine, body, parkingspot
            FROM player_vehicles
            WHERE plate = ? AND citizenid = ? AND garage = ? AND state = 1
        ]], { plate, Player.PlayerData.citizenid, lot.id })

        if not row then return false, 'That vehicle is not in this lot' end
    end

    local spotIndex = pickSpot(lot, tonumber(row.parkingspot))
    if not spotIndex then return false, 'Every spot in this lot is taken' end

    local spot = lot.spots[spotIndex]
    local vehicle = CreateVehicleServerSetter(
        joaat(row.vehicle), getVehicleType(row.vehicle), spot.x, spot.y, spot.z, spot.w
    )

    --- Hand the fee back. Anything that fails after payment has to do this, or
    --- the pound keeps the money and the car.
    local function refund()
        if fee then Player.Functions.AddMoney('cash', fee, 'jgrp-garage:impound-refund') end
    end

    if not vehicle or vehicle == 0 then
        refund()
        return false, 'Could not spawn that vehicle'
    end

    local timeout = 0

    while not DoesEntityExist(vehicle) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end

    if not DoesEntityExist(vehicle) then
        refund()
        return false, 'Could not spawn that vehicle'
    end

    SetVehicleNumberPlateText(vehicle, plate)

    -- Clearing `depotprice` is what takes it out of the pound: the next listing
    -- is keyed on that column, so a released car stops appearing without
    -- anything else being written.
    if lot.impound then
        MySQL.update.await(
            'UPDATE player_vehicles SET state = 0, depotprice = 0 WHERE plate = ? AND citizenid = ?',
            { plate, Player.PlayerData.citizenid }
        )
    else
        MySQL.update.await(
            'UPDATE player_vehicles SET state = 0 WHERE plate = ? AND citizenid = ?',
            { plate, Player.PlayerData.citizenid }
        )
    end

    local props = row.mods and json.decode(row.mods) or {}

    return true, {
        netId = NetworkGetNetworkIdFromEntity(vehicle),
        plate = plate,
        props = props,
        fuel = row.fuel or 100,
        spotIndex = spotIndex,
        wasPreferred = tonumber(row.parkingspot) == spotIndex,
        fee = fee
    }
end)

-- ---------------------------------------------------------------------------
-- The police side
-- ---------------------------------------------------------------------------

--- Seized vehicles, for qb-policejob's impound menu.
---
--- Registered under qb-garages' name on purpose: qb-policejob has always asked
--- `qb-garages:server:GetDepotVehiclesPD` for this list, and **nothing has ever
--- answered it** -- the callback was called but never defined, in qb-garages or
--- anywhere else, so that menu has been dead the whole time. Answering it here
--- costs nothing and makes it work.
QBCore.Functions.CreateCallback('qb-garages:server:GetDepotVehiclesPD', function(source, cb)
    local Player = getPlayer(source)
    if not Player then return cb({}) end

    local rows = MySQL.query.await([[
        SELECT plate, vehicle, fuel, engine, body, depotprice, state
        FROM player_vehicles
        WHERE state = 2
        ORDER BY plate
    ]])

    cb(rows or {})
end)

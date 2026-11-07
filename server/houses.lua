--[[
    Server side of house garages. Nothing is cached: a house lot is resolved from
    the housing tables on every request, so a sale, a new key or a moved garage
    takes effect immediately and the client can never name a house it has no
    right to. See shared/houses.lua.
]]

local QBCore = exports['qb-core']:GetCoreObject()

JGRPGarage.House = {}

local tableExists = {}

local function hasTable(name)
    if tableExists[name] == nil then
        local n = MySQL.scalar.await([[
            SELECT COUNT(*) FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
        ]], { name })
        tableExists[name] = (n or 0) > 0
    end

    return tableExists[name]
end

--- Does `tbl` have every one of `columns`? The live `properties` table is not always
--- sofy-housing's (an older or different script's table can share the name), and a
--- missing column would throw on every poll. Checked once per table.
local columnsOk = {}

local function hasColumns(tbl, columns)
    if columnsOk[tbl] == nil then
        local found = MySQL.query.await([[
            SELECT COLUMN_NAME FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
        ]], { tbl }) or {}

        local have = {}
        for _, r in ipairs(found) do have[r.COLUMN_NAME] = true end

        local missing = {}
        for _, c in ipairs(columns) do
            if not have[c] then missing[#missing + 1] = c end
        end

        columnsOk[tbl] = #missing == 0

        if #missing > 0 then
            print(('^3[jgrp-garage]^7 `%s` is missing column(s) %s -- house garages from that table are off')
                :format(tbl, table.concat(missing, ', ')))
        end
    end

    return columnsOk[tbl]
end

local SOFY_COLUMNS = { 'property_id', 'owner_citizenid', 'street', 'has_access', 'garage_data' }
local QB_HOUSE_COLUMNS = { 'name', 'label', 'garage' }
local QB_OWNER_COLUMNS = { 'house', 'citizenid', 'keyholders' }

local function decode(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return nil end

    local ok, result = pcall(json.decode, value)
    return ok and type(result) == 'table' and result or nil
end

local function listHas(list, citizenid)
    if type(list) ~= 'table' then return false end

    for k, v in pairs(list) do
        if v == citizenid or (v == true and k == citizenid) then return true end
        if type(v) == 'table' and v.citizenid == citizenid then return true end
    end

    return false
end

local function build(id, label, garage, legacy, owner, keys)
    local raw = JGRPGarage.MakeHouseRaw(id, label, garage, legacy)
    if not raw then return nil end

    local lot = JGRPGarage.BuildLot(id, raw)
    if not lot then return nil end

    lot.owner, lot.keys = owner, keys
    lot.houseGarage = garage

    return lot
end

--- Fresh lot for a house id, with the owner and key list attached, or nil.
local function resolve(id)
    local pid = id:match('^house_sofy_(%d+)$')

    if pid then
        if not (hasTable('properties') and hasColumns('properties', SOFY_COLUMNS)) then return nil end

        local row = MySQL.single.await(
            'SELECT street, owner_citizenid, has_access, garage_data FROM properties WHERE property_id = ?',
            { tonumber(pid) }
        )
        if not row then return nil end

        return build(id, ('%s%s Garage'):format(row.street or '', pid), decode(row.garage_data),
            pid, row.owner_citizenid, decode(row.has_access))
    end

    local name = id:match('^house_qb_(.+)$')

    if name then
        if not (hasTable('houselocations') and hasTable('player_houses')
            and hasColumns('houselocations', QB_HOUSE_COLUMNS) and hasColumns('player_houses', QB_OWNER_COLUMNS)) then return nil end

        local row = MySQL.single.await([[
            SELECT hl.label, hl.garage, ph.citizenid, ph.keyholders
            FROM houselocations hl
            LEFT JOIN player_houses ph ON ph.house = hl.name
            WHERE hl.name = ?
            LIMIT 1
        ]], { name })
        if not row then return nil end

        return build(id, ('%s Garage'):format(row.label or name), decode(row.garage),
            (name:lower():gsub(' ', '')), row.citizenid, decode(row.keyholders))
    end

    return nil
end

--- Is this citizen allowed in the house's garage?
function JGRPGarage.House.CanUse(lot, citizenid)
    if not (lot and lot.house and citizenid) then return false end

    return lot.owner == citizenid or listHas(lot.keys, citizenid)
end

-- Lots whose id starts with 'house_' do not live in Config.Lots; look them up.
local baseGetLot = JGRPGarage.GetLot

function JGRPGarage.GetLot(id)
    local lot = baseGetLot(id)
    if lot or type(id) ~= 'string' or id:sub(1, 6) ~= 'house_' then return lot end

    return resolve(id)
end

--- Every house garage this citizen owns or has a key to, in the compact form the
--- client rebuilds a lot from.
local function listFor(citizenid)
    local out = {}

    if hasTable('properties') and hasColumns('properties', SOFY_COLUMNS) then
        local rows = MySQL.query.await([[
            SELECT property_id, street, garage_data FROM properties
            WHERE garage_data IS NOT NULL
              AND (owner_citizenid = ? OR has_access LIKE CONCAT('%"', ?, '"%'))
        ]], { citizenid, citizenid })

        for _, row in ipairs(rows or {}) do
            local g = decode(row.garage_data)
            local id = 'house_sofy_' .. row.property_id

            if JGRPGarage.MakeHouseRaw(id, 'x', g) then
                out[#out + 1] = {
                    id = id,
                    label = ('%s%s Garage'):format(row.street or '', row.property_id),
                    g = g,
                    legacy = tostring(row.property_id)
                }
            end
        end
    end

    if hasTable('houselocations') and hasTable('player_houses')
        and hasColumns('houselocations', QB_HOUSE_COLUMNS) and hasColumns('player_houses', QB_OWNER_COLUMNS) then
        local rows = MySQL.query.await([[
            SELECT hl.name, hl.label, hl.garage
            FROM player_houses ph
            JOIN houselocations hl ON hl.name = ph.house
            WHERE ph.citizenid = ? OR ph.keyholders LIKE CONCAT('%"', ?, '"%')
        ]], { citizenid, citizenid })

        for _, row in ipairs(rows or {}) do
            local g = decode(row.garage)
            local id = 'house_qb_' .. row.name

            if JGRPGarage.MakeHouseRaw(id, 'x', g) then
                out[#out + 1] = {
                    id = id,
                    label = ('%s Garage'):format(row.label or row.name),
                    g = g,
                    legacy = (row.name:lower():gsub(' ', ''))
                }
            end
        end
    end

    return out
end

lib.callback.register('jgrp-garage:server:getHouseLots', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return {} end

    return listFor(Player.PlayerData.citizenid)
end)

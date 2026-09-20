--[[
    Normalises every Config.Lots entry into one shape that both sides agree on.

    Whatever form the bounds were written in -- polygon or box -- they come out of
    here as a flat XY polygon plus a Z range, so the client can build an ox_lib zone
    from it and the server can re-check the same bounds without trusting the client.
]]

JGRPGarage = JGRPGarage or {}

local function rotate2d(x, y, degrees)
    local rad = math.rad(degrees)
    local c, s = math.cos(rad), math.sin(rad)
    return x * c - y * s, x * s + y * c
end

--- @return table? polygon, number? minZ, number? maxZ
local function normaliseBounds(bounds)
    if not bounds then return nil end

    local polygon = {}

    if bounds.points then
        if #bounds.points < 3 then return nil end

        local thickness = (bounds.thickness or 8.0) * 0.5
        local minZ, maxZ

        for i = 1, #bounds.points do
            local point = bounds.points[i]
            polygon[i] = { x = point.x + 0.0, y = point.y + 0.0 }

            if not minZ or point.z < minZ then minZ = point.z end
            if not maxZ or point.z > maxZ then maxZ = point.z end
        end

        return polygon, minZ - thickness, maxZ + thickness
    end

    if bounds.center then
        local size = bounds.size or vec3(30.0, 30.0, 10.0)
        local halfX, halfY = size.x * 0.5, size.y * 0.5
        local rotation = bounds.rotation or 0.0

        local corners = {
            { halfX, halfY }, { -halfX, halfY }, { -halfX, -halfY }, { halfX, -halfY }
        }

        for i = 1, 4 do
            local x, y = rotate2d(corners[i][1], corners[i][2], rotation)
            polygon[i] = { x = bounds.center.x + x, y = bounds.center.y + y }
        end

        return polygon, bounds.center.z - size.z * 0.5, bounds.center.z + size.z * 0.5
    end

    return nil
end

--- Standard even-odd ray cast. `polygon` is an array of { x = , y = }.
local function pointInPolygon(polygon, x, y)
    local inside = false
    local count = #polygon
    local j = count

    for i = 1, count do
        local a, b = polygon[i], polygon[j]

        if (a.y > y) ~= (b.y > y) and x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x then
            inside = not inside
        end

        j = i
    end

    return inside
end

local function buildLots()
    local lots = {}

    for id, raw in pairs(Config.Lots or {}) do
        local polygon, minZ, maxZ = normaliseBounds(raw.bounds)

        if not polygon then
            print(('^1[jgrp-garage]^7 lot "%s" has no usable bounds -- skipped'):format(id))
            goto continue
        end

        if type(raw.spots) ~= 'table' or #raw.spots == 0 then
            print(('^1[jgrp-garage]^7 lot "%s" has no spots -- skipped'):format(id))
            goto continue
        end

        do
            -- Centre of the bounds, and the distance from it to the furthest corner.
            -- Used for the blip, and as a cheap first-pass distance check.
            local sumX, sumY = 0.0, 0.0

            for i = 1, #polygon do
                sumX = sumX + polygon[i].x
                sumY = sumY + polygon[i].y
            end

            local centreX, centreY = sumX / #polygon, sumY / #polygon
            local radius = 0.0

            for i = 1, #polygon do
                local dx, dy = polygon[i].x - centreX, polygon[i].y - centreY
                local distance = math.sqrt(dx * dx + dy * dy)
                if distance > radius then radius = distance end
            end

            local spots = {}

            for i = 1, #raw.spots do
                local spot = raw.spots[i]
                spots[i] = {
                    x = spot.x + 0.0,
                    y = spot.y + 0.0,
                    z = spot.z + 0.0,
                    w = (spot.w or 0.0) + 0.0
                }
            end

            lots[id] = {
                id = id,
                label = raw.label or id,
                polygon = polygon,
                minZ = minZ,
                maxZ = maxZ,
                centre = vec3(centreX, centreY, (minZ + maxZ) * 0.5),
                radius = radius,
                spots = spots,
                blip = raw.blip,
                classes = raw.classes,

                -- Carried through explicitly, like everything else here. This
                -- builder copies named fields rather than the raw table, so a
                -- flag that is not listed is silently dropped -- which is how
                -- the impound spent its first outing behaving as an ordinary
                -- parking lot with an ordinary label.
                impound = raw.impound == true
            }
        end

        ::continue::
    end

    return lots
end

JGRPGarage.Lots = buildLots()

function JGRPGarage.GetLot(id)
    return id and JGRPGarage.Lots[id] or nil
end

--- Is `coords` inside this lot's bounds?
function JGRPGarage.IsInsideLot(lot, coords, tolerance)
    if not lot then return false end

    tolerance = tolerance or 0.0

    if coords.z < lot.minZ - tolerance or coords.z > lot.maxZ + tolerance then
        return false
    end

    if pointInPolygon(lot.polygon, coords.x, coords.y) then
        return true
    end

    -- Tolerance is only meaningful outside the polygon when the player is stood
    -- right on the edge, so fall back to the bounding radius for that case.
    if tolerance > 0.0 then
        local dx, dy = coords.x - lot.centre.x, coords.y - lot.centre.y
        return math.sqrt(dx * dx + dy * dy) <= lot.radius + tolerance
    end

    return false
end

--- Index of the spot `coords` is sitting in, or nil. Ties go to the nearest spot.
function JGRPGarage.GetSpotAt(lot, coords, radius)
    if not lot then return nil end

    radius = radius or Config.SpotRadius
    local best, bestDistance

    for index = 1, #lot.spots do
        local spot = lot.spots[index]
        local distance = #(coords - vec3(spot.x, spot.y, spot.z))

        if distance <= radius and (not bestDistance or distance < bestDistance) then
            best, bestDistance = index, distance
        end
    end

    return best
end

function JGRPGarage.IsClassAllowed(lot, class)
    if not lot or not lot.classes or not class then return true end

    for i = 1, #lot.classes do
        if lot.classes[i] == class then return true end
    end

    return false
end

--- Where a retrieved vehicle should come out.
---
--- `remembered` is the spot it was parked in, `occupied` a set of spot indexes
--- that currently have a car on them. The remembered spot wins if it is free;
--- otherwise the search walks forward from it and wraps, so the car reappears as
--- close as possible to where its owner left it. Returns nil when the lot is full.
function JGRPGarage.PickSpot(lot, remembered, occupied)
    if not lot then return nil end

    occupied = occupied or {}
    local total = #lot.spots

    if remembered and remembered >= 1 and remembered <= total and not occupied[remembered] then
        return remembered
    end

    local start = remembered or 0

    for offset = 1, total do
        local index = ((start + offset - 1) % total) + 1

        if not occupied[index] then return index end
    end

    return nil
end

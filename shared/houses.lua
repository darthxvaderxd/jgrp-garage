--[[
    House garages.

    qb-houses and sofy-housing both announce their garage to `qb-garages`, which
    is retired, so nothing could be parked at a house. jgrp-garage now builds a
    lot for each house garage the player owns or holds a key to, using the same
    spot logic as the fixed lots. Shared so the client rebuilds exactly the lot
    the server validates against.

    A house garage is one point (x, y, z, heading) and, for sofy-housing, a
    length/width. Spot 1 is that point; further spots (Config.HouseSpots) step
    sideways from it, alternating right and left.
]]

JGRPGarage = JGRPGarage or {}

--- @param id string       'house_sofy_<property_id>' or 'house_qb_<house name>'
--- @param label string
--- @param g table         { x, y, z, h, length?, width? }
--- @param legacy string?  the `garage` value qb-garages stored for this house
--- @return table? raw     a Config.Lots-shaped entry, or nil when g is unusable
function JGRPGarage.MakeHouseRaw(id, label, g, legacy)
    if type(g) ~= 'table' then return nil end

    local x, y, z = tonumber(g.x), tonumber(g.y), tonumber(g.z)
    if not (x and y and z) or (x == 0.0 and y == 0.0) then return nil end

    local heading = tonumber(g.h) or tonumber(g.w) or 0.0
    local size = math.max(tonumber(g.length) or 0.0, tonumber(g.width) or 0.0) + 8.0
    if size < 14.0 then size = 14.0 end

    local count = math.max(1, math.floor(Config.HouseSpots or 2))
    local step = Config.HouseSpotSpacing or 3.2
    local rad = math.rad(heading)
    local rx, ry = math.cos(rad), math.sin(rad)

    local spots = {}

    for i = 1, count do
        -- 0, +1, -1, +2, -2 ... steps along the lateral axis
        local k = (i % 2 == 0) and (i / 2) or -((i - 1) / 2)
        spots[i] = {
            x = x + rx * step * k,
            y = y + ry * step * k,
            z = z,
            w = heading
        }
    end

    return {
        label = label,
        bounds = { center = vec3(x, y, z), size = vec3(size, size, 8.0), rotation = 0.0 },
        spots = spots,
        house = true,
        legacyGarage = legacy
    }
end

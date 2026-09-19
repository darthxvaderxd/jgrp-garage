# jgrp-garage

Parking-lot garages for QBCore. A lot is defined by its **bounds** and an **array of
spots**; cars remember which spot they were left in and return to it.

- Sit in a spot in your car → **Park Vehicle** appears in the radial menu.
- Stand anywhere inside the lot → **Parking Lot** appears, listing your stored cars.
- Pull a car out and it returns to its own spot. If something else is sitting there,
  it takes the next open spot in the array instead.

## Requires

`qb-core`, `ox_lib`, `oxmysql`, and `qb-radialmenu` for the radial options (without it
the resource still starts and falls back to `/park` and `/parking`).

## Install

1. `ensure jgrp-garage` in `resources.cfg`.
2. Start it once. It adds the `parkingspot` column to `player_vehicles` itself and
   prints a line when it does. `install.sql` has the same statement if you prefer to
   apply it by hand.

## Defining a lot

Bounds come in two forms. A polygon outline:

```lua
bounds = {
    points = {
        vec3(200.0, -788.0, 30.5),
        vec3(240.0, -788.0, 30.5),
        vec3(240.0, -815.0, 30.5),
        vec3(200.0, -815.0, 30.5)
    },
    thickness = 10.0   -- vertical height of the zone
}
```

…or a box:

```lua
bounds = {
    center = vec3(270.0, -333.0, 44.7),
    size = vec3(30.0, 20.0, 10.0),
    rotation = 0.0
}
```

Spots are `vector4`, one per bay. **The order matters** — it is the order a car falls
back through when its own spot is taken:

```lua
spots = {
    vec4(222.02, -804.19, 30.26, 248.19),
    vec4(223.93, -799.11, 30.25, 248.53)
}
```

Optional per lot:

- `blip = { label, sprite, colour, scale }` — **omit the key entirely, or set it to
  `false`, and the lot gets no map blip.**
- `classes = Config.VehicleClasses['car']` — restricts what may park there. Enforced
  on the server against qb-core's own category data, not just client-side.

## Debug mode

Set `Config.Debug = true` and restart the resource. For every lot within ~60m:

- the **bounds** are drawn as a wireframe — floor outline, ceiling outline and corner
  posts, so you can see the exact volume without it blocking your view of the lot
- every **spot** gets a marker, **green when free and red when a car is sitting on
  it**, using the same proximity rule the server uses to decide where a retrieved car
  comes out — so the debug view shows you what the fallback will actually do
- the lot id, label and spot count float at the centre; each spot is labelled with its
  index when you are close

It also prints a summary of every loaded lot to the console on start, including
whether each one has a blip:

```
[jgrp-garage] debug on, 14 lot(s) loaded
  pillbox         "Pillbox Parking"    61 spots  4 bounds points  z 25.5..35.5  blip: yes
  route_68_motel  "Route 68 Motel"     10 spots  4 bounds points  z 39.7..49.7  blip: yes
  ...
```

14 lots, 483 spots in total.

ox_lib's own zone debug is deliberately not used — it fills the whole volume with
solid polygons, which hides the spots inside a car park.

## Capturing coordinates

With `Config.Debug = true`, four commands are available:

| Command | What it does |
| --- | --- |
| `/parkbounds` | records your position as a bounds corner — walk the outline |
| `/parkspot` | records your vehicle's position and heading as a spot |
| `/parkdump` | prints a ready-to-paste `Config.Lots` entry to the F8 console |
| `/parkclear` | throws away what you have captured so far |

## Notes

- Ships with **14 lots** using coordinates taken from the server's existing
  `qb-garages` config, so they are known-good: `pillbox`, `pillbox_garage`,
  `pink_cage_parking`, `rockford_garage`, `red_garage_floor1`,
  `white_garage_floor1`, `spanish_garage`, `casino_garage`, `beach_garage`,
  `clinton_garage`, `mirror_park_garage`, `occupation_garage`,
  `route_68_motel` and `great_ocean_parking`.
- Runs alongside `qb-garages` — it only touches rows whose `garage` is one of its own
  lot ids. Note that `qb-garages` has `Config.SharedGarages = true`, so its menus list
  vehicles by `citizenid` regardless of garage and will also show cars parked here.
- `Config.RestoreOnStart` is off by default. Turning it on makes the resource mark
  every vehicle in a jgrp lot as stored again on restart.
- The only places it touches other resources are `Config.GetFuel`, `Config.SetFuel`
  and `Config.GiveKey` at the top of `config.lua` — currently `sofy-fuel` and
  `vehiclekeys:client:SetOwner`. All three run **client-side**.

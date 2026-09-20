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

## The impound

One lot in `Config.Lots` carries `impound = true`, and it behaves differently
from the rest:

- **You cannot park there.** The Park option never appears, and the server
  refuses a park aimed at it.
- **What it lists is whatever the police have impounded** — your vehicles with
  a `depotprice` on them, wherever they were parked when they were taken.
- **Taking one back costs the fee the police set**, cash first and then bank,
  the order qb-garages used. The fee is taken before the car is spawned and
  handed back if the spawn fails.
- Releasing clears `depotprice`, which is what takes the car out of the pound —
  the listing is keyed on that column, so nothing else needs writing.

It sits on **qb-garages' own `depotLot` coordinates** (671.38, 233.19, 94.2),
deliberately: players already know to go there, so taking the impound over
rather than moving it means nobody has to be told anything.

**Impounding is qb-policejob's job, not this one's.** It writes `depotprice`
straight onto `player_vehicles`, which is why the pound keeps working with
qb-garages gone. This lot is only the counter you pay at.

`Config.ImpoundFallbackPrice` (500) covers a row that arrived with no fee set.

### Cars left out when the server restarts

`Config.ImpoundOnStart` (on) impounds every vehicle that was still out in the
world (`state = 0`) when the resource starts, at `Config.ImpoundOnStartPrice`
($250).

Those cars have no entity any more and nobody parked them, so the choice is
between quietly marking them stored — a free garage for anyone who logs off in
the street — and towing them. This is the tow, which is what qb-garages did.

A fee the police already set is **never overwritten**: `depotprice > 0` means
the car was impounded for a reason, and a restart should not make it cheaper or
dearer to get back.

It is mutually exclusive with `Config.RestoreOnStart`, which puts those same
cars back in their lots instead. They disagree about the same rows, so if both
are on, impounding wins.

### The PD impound menu

`qb-policejob` asks `qb-garages:server:GetDepotVehiclesPD` for the list of
seized (`state = 2`) vehicles. **Nothing has ever answered that callback** — it
is called in `policeimpound.lua` and defined nowhere, in qb-garages or anywhere
else, so that menu has been dead for as long as it has existed. jgrp-garage now
registers it under the same name, so it works.

-- jgrp-garage: house garages (qb-houses + sofy-housing)
--
-- No schema change is needed -- the `parkingspot` column is added by the resource
-- itself. This file only RE-POINTS cars that were stored in a house garage while
-- qb-garages was running, so they carry jgrp-garage's house lot ids:
--
--     sofy-housing   '12'      ->  'house_sofy_12'
--     qb-houses      'lowend1' ->  'house_qb_lowend1'   (qb-garages lower-cased the name
--                                                         and removed spaces; the house
--                                                         name is matched the same way)
--
-- It is OPTIONAL: jgrp-garage already lists cars under the old value too. Run it once
-- if you want the table tidy. Safe to run twice (the second run matches nothing).
-- Only parked cars (state = 1) are touched.

-- 1. Preview: what would change. Should list the cars you expect.
SELECT pv.plate, pv.citizenid, pv.garage AS old_garage,
       CONCAT('house_sofy_', p.property_id) AS new_garage
FROM player_vehicles pv
JOIN properties p ON pv.garage = CAST(p.property_id AS CHAR)
WHERE pv.state = 1 AND p.garage_data IS NOT NULL
UNION ALL
SELECT pv.plate, pv.citizenid, pv.garage, CONCAT('house_qb_', hl.name)
FROM player_vehicles pv
JOIN houselocations hl ON pv.garage = LOWER(REPLACE(hl.name, ' ', ''))
WHERE pv.state = 1;

-- 2. Backup of the rows about to change.
CREATE TABLE IF NOT EXISTS player_vehicles_garage_backup_20261102 AS
SELECT plate, citizenid, garage, state, parkingspot FROM player_vehicles
WHERE state = 1 AND (
    garage IN (SELECT CAST(property_id AS CHAR) FROM properties WHERE garage_data IS NOT NULL)
 OR garage IN (SELECT LOWER(REPLACE(name, ' ', '')) FROM houselocations)
);

-- 3. The migration.
UPDATE player_vehicles pv
JOIN properties p ON pv.garage = CAST(p.property_id AS CHAR)
SET pv.garage = CONCAT('house_sofy_', p.property_id)
WHERE pv.state = 1 AND p.garage_data IS NOT NULL;

UPDATE player_vehicles pv
JOIN houselocations hl ON pv.garage = LOWER(REPLACE(hl.name, ' ', ''))
SET pv.garage = CONCAT('house_qb_', hl.name)
WHERE pv.state = 1;

-- Undo (only if needed):
-- UPDATE player_vehicles pv JOIN player_vehicles_garage_backup_20261102 b ON b.plate = pv.plate
-- SET pv.garage = b.garage;

-- jgrp-garage stores which bay a vehicle was left in, so it can be returned there.
-- The resource adds this column itself on first start; this file is only here if
-- you would rather apply it by hand.

ALTER TABLE `player_vehicles` ADD COLUMN `parkingspot` INT NULL DEFAULT NULL;

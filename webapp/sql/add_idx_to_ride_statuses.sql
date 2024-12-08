SET CHARACTER_SET_CLIENT = utf8mb4;
SET CHARACTER_SET_CONNECTION = utf8mb4;

ALTER TABLE ride_statuses ADD INDEX ride_id_idx (ride_id);

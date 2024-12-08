ALTER TABLE chairs
ADD COLUMN total_distance DOUBLE DEFAULT 0,
ADD COLUMN total_distance_updated_at DATETIME DEFAULT NULL;

-- 椅子の移動距離を累積するトリガー
DELIMITER //
CREATE TRIGGER update_total_distance
AFTER INSERT ON chair_locations
FOR EACH ROW
BEGIN
    DECLARE distance DOUBLE DEFAULT 0;

    -- 現在のレコードと直前のレコードから距離を計算
    SELECT ABS(NEW.latitude - latitude) + ABS(NEW.longitude - longitude)
    INTO distance
    FROM chair_locations
    WHERE chair_id = NEW.chair_id AND created_at < NEW.created_at
    ORDER BY created_at DESC
    LIMIT 1;

    -- `total_distance` を累積
    UPDATE chairs
    SET total_distance = total_distance + IFNULL(distance, 0),
        total_distance_updated_at = NOW()
    WHERE id = NEW.chair_id;
END;
//
DELIMITER ;

-- chair_locations データを一時テーブルにバックアップ
CREATE TEMPORARY TABLE temp_chair_locations AS
SELECT * FROM chair_locations;

-- 元のデータを削除
DELETE FROM chair_locations;

-- データを再挿入してトリガーを発火
INSERT INTO chair_locations (id, chair_id, latitude, longitude, created_at)
SELECT id, chair_id, latitude, longitude, created_at
FROM temp_chair_locations;

-- 一時テーブルを削除
DROP TEMPORARY TABLE temp_chair_locations;

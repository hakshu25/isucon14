# frozen_string_literal: true

require 'isuride/base_handler'

module Isuride
  class InternalHandler < BaseHandler
    get '/matching' do
      ride = db.query('SELECT * FROM rides WHERE chair_id IS NULL ORDER BY created_at LIMIT 1 FOR UPDATE').first
      halt 204 unless ride

      # 目的地座標の取得
      destination_lat = ride.fetch(:destination_latitude)
      destination_lon = ride.fetch(:destination_longitude)

      # 椅子候補を取得し、最速到着時間を算出
      chairs = db.xquery(<<~SQL, ride.fetch(:id))
        SELECT
          chairs.id,
          chairs.name,
          chair_models.speed,
          chair_locations.latitude AS current_lat,
          chair_locations.longitude AS current_lon,
          (
            SELECT COUNT(*) = 0
            FROM (
              SELECT COUNT(chair_sent_at) = 6 AS completed
              FROM ride_statuses
              WHERE ride_id IN (
                SELECT id
                FROM rides
                WHERE chair_id = chairs.id
              )
              GROUP BY ride_id
            ) is_completed
            WHERE completed = FALSE
          ) AS is_available
        FROM chairs
        INNER JOIN chair_models ON chairs.model = chair_models.name
        LEFT JOIN chair_locations ON chairs.id = chair_locations.chair_id
        WHERE chairs.is_active = TRUE
      SQL

      # 到着時間を計算して、最速の椅子を選択
      best_chair = chairs
                   .select { |chair| chair.fetch(:is_available) == 1 }
                   .min_by do |chair|
                     distance = calculate_distance(
                       chair.fetch(:current_lat), chair.fetch(:current_lon),
                       destination_lat, destination_lon
                     )
                     distance.to_f / chair.fetch(:speed)
                   end

      halt 204 unless best_chair

      # 最適な椅子をライドに割り当て
      db.xquery('UPDATE rides SET chair_id = ? WHERE id = ?', best_chair.fetch(:id), ride.fetch(:id))

      status 204
    end
  end
end

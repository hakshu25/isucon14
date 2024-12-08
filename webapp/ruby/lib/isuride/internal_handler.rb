# frozen_string_literal: true

require 'isuride/base_handler'

module Isuride
  class InternalHandler < BaseHandler
    # このAPIをインスタンス内から一定間隔で叩かせることで、椅子とライドをマッチングさせる
    # GET /api/internal/matching
    get '/matching' do
      # 未割り当てのライドを取得（最も古いものから）
      ride = db.query('SELECT * FROM rides WHERE chair_id IS NULL ORDER BY created_at LIMIT 1').first
      unless ride
        halt 204
      end

      # 目的地の座標を取得
      destination_latitude = ride[:destination_latitude]
      destination_longitude = ride[:destination_longitude]

      unless destination_latitude && destination_longitude
        halt 400, 'Ride destination coordinates are missing'
      end

      # アクティブな椅子とそのモデル速度、現在の位置を取得
      chairs = db.query(<<~SQL)
        SELECT chairs.id, chairs.name, chairs.model, chair_models.speed,
              chair_locations.latitude AS current_latitude,
              chair_locations.longitude AS current_longitude
        FROM chairs
        JOIN chair_models ON chairs.model = chair_models.name
        LEFT JOIN (
          SELECT chair_id, latitude, longitude
          FROM chair_locations
          WHERE (chair_id, created_at) IN (
            SELECT chair_id, MAX(created_at)
            FROM chair_locations
            GROUP BY chair_id
          )
        ) AS chair_locations ON chairs.id = chair_locations.chair_id
        WHERE chairs.is_active = TRUE
      SQL

      best_chair = nil
      min_time = Float::INFINITY

      # 椅子ごとの到着時間を計算
      chairs.each do |chair|
        # 必要な情報がない場合はスキップ
        next if chair[:current_latitude].nil? || chair[:current_longitude].nil?
        next if chair[:speed].nil? || chair[:speed] <= 0

        # 距離を計算
        distance = calculate_distance(
          chair[:current_latitude], chair[:current_longitude],
          destination_latitude, destination_longitude
        )

        # 時間を計算
        time = distance / chair[:speed].to_f
        if time < min_time
          min_time = time
          best_chair = chair
        end
      end

      # 最適な椅子が見つからなかった場合
      unless best_chair
        halt 204
      end

      # 最適な椅子をライドに割り当てる
      db_transaction do |tx|
        tx.xquery('UPDATE rides SET chair_id = ? WHERE id = ?', best_chair[:id], ride[:id])
      end

      halt 204
    end
  end
end

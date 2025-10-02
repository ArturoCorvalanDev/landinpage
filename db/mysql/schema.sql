-- MySQL schema for BLE simulation (devices, events, witnesses, routes, alerts)
-- Requires MySQL 8.0+

SET NAMES utf8mb4;
SET time_zone = "+00:00";

-- Adjust db name as needed
CREATE DATABASE IF NOT EXISTS `ble_sim`
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_0900_ai_ci;
USE `ble_sim`;

-- Devices currently known by the system
CREATE TABLE IF NOT EXISTS `devices` (
  `id`            VARCHAR(64)  NOT NULL,
  `name`          VARCHAR(100) NOT NULL,
  `created_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Optional: time-series of device positions (for history/debug)
CREATE TABLE IF NOT EXISTS `device_positions` (
  `id`           BIGINT       NOT NULL AUTO_INCREMENT,
  `device_id`    VARCHAR(64)  NOT NULL,
  `lat`          DECIMAL(9,6) NOT NULL,
  `lng`          DECIMAL(9,6) NOT NULL,
  `rssi`         INT          NULL,
  `recorded_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_device_positions_device_time` (`device_id`, `recorded_at`),
  CONSTRAINT `fk_device_positions_device`
    FOREIGN KEY (`device_id`) REFERENCES `devices`(`id`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Device-centric events (disappeared / reappeared)
CREATE TABLE IF NOT EXISTS `device_events` (
  `id`          BIGINT        NOT NULL AUTO_INCREMENT,
  `device_id`   VARCHAR(64)   NOT NULL,
  `event_type`  ENUM('disappeared','reappeared') NOT NULL,
  `event_lat`   DECIMAL(9,6)  NOT NULL,
  `event_lng`   DECIMAL(9,6)  NOT NULL,
  `from_lat`    DECIMAL(9,6)  NULL,
  `from_lng`    DECIMAL(9,6)  NULL,
  `body_text`   VARCHAR(255)  NULL,
  `created_at`  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_device_events_device_time` (`device_id`, `created_at`),
  CONSTRAINT `fk_device_events_device`
    FOREIGN KEY (`device_id`) REFERENCES `devices`(`id`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Top-10 witnesses snapshot per device event
CREATE TABLE IF NOT EXISTS `device_event_witnesses` (
  `id`                  BIGINT       NOT NULL AUTO_INCREMENT,
  `event_id`            BIGINT       NOT NULL,
  `witness_device_id`   VARCHAR(64)  NULL,
  `witness_lat`         DECIMAL(9,6) NOT NULL,
  `witness_lng`         DECIMAL(9,6) NOT NULL,
  `distance_meters`     DOUBLE       NOT NULL,
  `rank_in_top10`       TINYINT      NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_event_witnesses_event` (`event_id`),
  CONSTRAINT `fk_event_witnesses_event`
    FOREIGN KEY (`event_id`) REFERENCES `device_events`(`id`)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_event_witnesses_device`
    FOREIGN KEY (`witness_device_id`) REFERENCES `devices`(`id`)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Route points (A->B) for a reappear device event
CREATE TABLE IF NOT EXISTS `device_reappear_route_points` (
  `id`         BIGINT       NOT NULL AUTO_INCREMENT,
  `event_id`   BIGINT       NOT NULL,
  `step_index` INT          NOT NULL,
  `lat`        DECIMAL(9,6) NOT NULL,
  `lng`        DECIMAL(9,6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_device_route_event_step` (`event_id`, `step_index`),
  CONSTRAINT `fk_device_route_event`
    FOREIGN KEY (`event_id`) REFERENCES `device_events`(`id`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- User-centric events (user disappeared / reappeared)
CREATE TABLE IF NOT EXISTS `user_events` (
  `id`          BIGINT        NOT NULL AUTO_INCREMENT,
  `event_type`  ENUM('disappeared','reappeared') NOT NULL,
  `event_lat`   DECIMAL(9,6)  NOT NULL,
  `event_lng`   DECIMAL(9,6)  NOT NULL,
  `from_lat`    DECIMAL(9,6)  NULL,
  `from_lng`    DECIMAL(9,6)  NULL,
  `created_at`  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_user_events_time` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Route points (A->B) for a user reappear event
CREATE TABLE IF NOT EXISTS `user_reappear_route_points` (
  `id`             BIGINT       NOT NULL AUTO_INCREMENT,
  `user_event_id`  BIGINT       NOT NULL,
  `step_index`     INT          NOT NULL,
  `lat`            DECIMAL(9,6) NOT NULL,
  `lng`            DECIMAL(9,6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user_route_event_step` (`user_event_id`, `step_index`),
  CONSTRAINT `fk_user_route_event`
    FOREIGN KEY (`user_event_id`) REFERENCES `user_events`(`id`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Alert center (mirrors local notifications in-app)
CREATE TABLE IF NOT EXISTS `alerts` (
  `id`         BIGINT        NOT NULL AUTO_INCREMENT,
  `alert_type` ENUM('device_disappeared','device_reappeared','user_disappeared','user_reappeared') NOT NULL,
  `title`      VARCHAR(200)  NOT NULL,
  `body`       TEXT          NULL,
  `payload`    JSON          NULL,
  `created_at` TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_alerts_time` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Convenience views (optional)
DROP VIEW IF EXISTS `v_last_device_position`;
CREATE VIEW `v_last_device_position` AS
SELECT dp.device_id,
       SUBSTRING_INDEX(GROUP_CONCAT(CONCAT(dp.lat, ',', dp.lng, ',', dp.rssi) ORDER BY dp.recorded_at DESC), ',', 1) AS last_lat,
       SUBSTRING_INDEX(SUBSTRING_INDEX(GROUP_CONCAT(CONCAT(dp.lat, ',', dp.lng, ',', dp.rssi) ORDER BY dp.recorded_at DESC), ',', 2), ',', -1) AS last_lng,
       SUBSTRING_INDEX(SUBSTRING_INDEX(GROUP_CONCAT(CONCAT(dp.lat, ',', dp.lng, ',', dp.rssi) ORDER BY dp.recorded_at DESC), ',', 3), ',', -1) AS last_rssi
FROM device_positions dp
GROUP BY dp.device_id;

-- Sample seed (optional, safe if run multiple times)
INSERT IGNORE INTO `devices` (`id`, `name`) VALUES
  ('FAKE:1', 'Device 1'),
  ('FAKE:2', 'Device 2'),
  ('FAKE:3', 'Device 3');


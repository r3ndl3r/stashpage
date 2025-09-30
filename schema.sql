-- StashPage Database Schema
-- A modern bookmark management system with user authentication and admin controls
-- 
-- Database Requirements:
-- - MariaDB 10.3+ or MySQL 8.0+
-- - UTF8MB4 character set for full Unicode support
-- - InnoDB storage engine for ACID compliance and foreign key support

-- ========================================
-- Database Setup and Configuration
-- ========================================

-- Ensure proper character set and collation for Unicode support
SET NAMES utf8mb4;
SET CHARACTER SET utf8mb4;

-- Create database if it doesn't exist
CREATE DATABASE IF NOT EXISTS stashpage 
  DEFAULT CHARACTER SET utf8mb4 
  DEFAULT COLLATE utf8mb4_unicode_ci;

USE stashpage;

-- ========================================
-- Core User Management System
-- ========================================

-- Users table: Central authentication and authorization system
-- Supports user registration, role-based access control, and approval workflows
CREATE TABLE users (
  id          INT(11) NOT NULL AUTO_INCREMENT COMMENT 'Primary key for user identification',
  username    VARCHAR(50) NOT NULL COMMENT 'Unique username for login authentication',
  password    VARCHAR(255) NOT NULL COMMENT 'Bcrypt hashed password for secure authentication',
  email       VARCHAR(100) DEFAULT NULL COMMENT 'User email address for notifications and recovery',
  is_admin    TINYINT(1) DEFAULT 0 COMMENT 'Administrative privileges flag (0=user, 1=admin)',
  status      ENUM('pending','approved') DEFAULT 'approved' COMMENT 'User account status for approval workflow',
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Account creation timestamp',
  
  PRIMARY KEY (id),
  UNIQUE KEY username (username),
  UNIQUE KEY unique_email (email),
  INDEX idx_status (status),
  INDEX idx_created_at (created_at)
) ENGINE=InnoDB 
  DEFAULT CHARSET=utf8mb4 
  COLLATE=utf8mb4_unicode_ci 
  COMMENT='User authentication and authorization system';

-- ========================================
-- Stash Data Storage System
-- ========================================

-- Stashes table: JSON-based bookmark storage with hierarchical organization
-- Each user has one unified stash containing all their organized bookmark categories
CREATE TABLE stashes (
  id          INT(11) NOT NULL AUTO_INCREMENT COMMENT 'Primary key for stash identification',
  user_id     INT(11) NOT NULL COMMENT 'Foreign key linking to users table',
  stash_data  LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL 
              COMMENT 'JSON document containing user bookmark categories and links'
              CHECK (json_valid(stash_data)),
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Initial stash creation timestamp',
  updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP 
              COMMENT 'Last modification timestamp for change tracking',
  
  PRIMARY KEY (id),
  UNIQUE KEY user_id (user_id),
  INDEX idx_updated_at (updated_at),
  
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    COMMENT 'Cascade delete ensures stash cleanup when user is removed'
) ENGINE=InnoDB 
  DEFAULT CHARSET=utf8mb4 
  COLLATE=utf8mb4_unicode_ci 
  COMMENT='User bookmark data storage with JSON document structure';

-- ========================================
-- Administrative Configuration System
-- ========================================

-- Admin settings table: Key-value configuration store for system settings
-- Supports dynamic application configuration without code changes
CREATE TABLE admin_settings (
  id           INT(11) NOT NULL AUTO_INCREMENT COMMENT 'Primary key for setting identification',
  setting_key  VARCHAR(100) NOT NULL COMMENT 'Unique configuration key identifier',
  setting_value TEXT DEFAULT NULL COMMENT 'Configuration value (supports complex data)',
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Setting creation timestamp',
  updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP 
               COMMENT 'Last modification timestamp for audit trail',
  
  PRIMARY KEY (id),
  UNIQUE KEY setting_key (setting_key),
  INDEX idx_updated_at (updated_at)
) ENGINE=InnoDB 
  DEFAULT CHARSET=utf8mb4 
  COLLATE=utf8mb4_unicode_ci 
  COMMENT='Administrative configuration key-value store';

-- ========================================
-- Security and Secrets Management
-- ========================================

-- App secrets table: Secure storage for application cryptographic keys
-- Contains sensitive data like session secrets and encryption keys
CREATE TABLE app_secrets (
  key_name     VARCHAR(50) NOT NULL COMMENT 'Secret identifier key',
  secret_value VARCHAR(255) DEFAULT NULL COMMENT 'Encrypted or hashed secret value',
  
  PRIMARY KEY (key_name)
) ENGINE=InnoDB 
  DEFAULT CHARSET=utf8mb4 
  COLLATE=utf8mb4_unicode_ci 
  COMMENT='Secure storage for application secrets and cryptographic keys';

-- Password reset tokens table: Secure password recovery system
-- Implements time-limited, single-use tokens for password reset functionality
CREATE TABLE password_reset_tokens (
  id         INT(11) NOT NULL AUTO_INCREMENT COMMENT 'Primary key for token identification',
  user_id    INT(11) NOT NULL COMMENT 'Foreign key linking to users table',
  token      VARCHAR(255) NOT NULL COMMENT 'Cryptographically secure reset token',
  expires_at TIMESTAMP NOT NULL COMMENT 'Token expiration time for security',
  used       TINYINT(1) DEFAULT 0 COMMENT 'Token usage flag (0=unused, 1=used)',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Token generation timestamp',
  
  PRIMARY KEY (id),
  INDEX idx_token (token),
  INDEX idx_expires_at (expires_at),
  INDEX idx_user_id (user_id),
  
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    COMMENT 'Cascade delete ensures token cleanup when user is removed'
) ENGINE=InnoDB 
  DEFAULT CHARSET=utf8mb4 
  COLLATE=utf8mb4_unicode_ci 
  COMMENT='Secure password reset token management system';

-- ========================================
-- Application Logging and Monitoring
-- ========================================

-- App logs table: Comprehensive application activity and error logging
-- Supports security monitoring, debugging, and compliance requirements
CREATE TABLE app_logs (
  id           INT(11) NOT NULL AUTO_INCREMENT COMMENT 'Primary key for log entry identification',
  level        ENUM('debug','info','warning','error','critical') NOT NULL 
               COMMENT 'Log severity level for filtering and alerting',
  category     VARCHAR(50) NOT NULL COMMENT 'Log category for organization (auth, system, etc.)',
  message      TEXT NOT NULL COMMENT 'Detailed log message with context information',
  user_id      INT(11) DEFAULT NULL COMMENT 'Associated user ID for user-specific events',
  username     VARCHAR(50) DEFAULT NULL COMMENT 'Username for quick reference without joins',
  ip_address   VARCHAR(45) DEFAULT NULL COMMENT 'Client IP address for security tracking (IPv4/IPv6)',
  user_agent   TEXT DEFAULT NULL COMMENT 'Client browser/application information',
  request_path VARCHAR(255) DEFAULT NULL COMMENT 'HTTP request path for request tracking',
  session_id   VARCHAR(100) DEFAULT NULL COMMENT 'Session identifier for request correlation',
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Log entry creation timestamp',
  
  PRIMARY KEY (id),
  INDEX idx_level (level),
  INDEX idx_category (category),
  INDEX idx_created_at (created_at),
  INDEX idx_user_id (user_id),
  INDEX idx_level_category (level, category)
) ENGINE=InnoDB 
  DEFAULT CHARSET=utf8mb4 
  COLLATE=utf8mb4_unicode_ci 
  COMMENT='Application activity and error logging system';

-- ========================================
-- Initial Data and Configuration
-- ========================================

-- Generate secure application secret for session management
-- This should be regenerated in production environments
INSERT INTO app_secrets (key_name, secret_value) 
VALUES ('mojo_app_secret', CONCAT(
  MD5(RAND()), 
  MD5(RAND()), 
  MD5(UNIX_TIMESTAMP()),
  MD5(CONNECTION_ID())
)) 
ON DUPLICATE KEY UPDATE secret_value = VALUES(secret_value);

-- Default administrative settings for initial deployment
INSERT INTO admin_settings (setting_key, setting_value) VALUES
('email_from_name', 'StashPage'),
('pushover_user_key', ''),
('pushover_app_token', ''),
('gmail_email', ''),
('gmail_app_password', '')
ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value);

-- ========================================
-- Database Optimization and Maintenance
-- ========================================

-- Log retention cleanup procedure (optional - run periodically)
-- Removes log entries older than 90 days to prevent unbounded growth
DELIMITER //
CREATE PROCEDURE CleanupOldLogs()
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;
  
  START TRANSACTION;
  DELETE FROM app_logs WHERE created_at < DATE_SUB(NOW(), INTERVAL 90 DAY);
  COMMIT;
END //
DELIMITER ;

-- Index optimization for large datasets
-- These indexes improve query performance for common operations
ALTER TABLE app_logs ADD INDEX idx_level_created (level, created_at);
ALTER TABLE password_reset_tokens ADD INDEX idx_expires_used (expires_at, used);

-- ========================================
-- Schema Information and Version
-- ========================================

-- Schema version tracking for future migrations
INSERT INTO admin_settings (setting_key, setting_value) 
VALUES ('schema_version', '1.0.0')
ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value);

-- Schema creation completion log
INSERT INTO app_logs (level, category, message) 
VALUES ('info', 'system', 'StashPage database schema created successfully');

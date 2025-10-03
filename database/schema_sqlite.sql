-- SQLite schema for Stashpage
-- Converted from MariaDB schema dump on 2025-10-03

-- Table: admin_settings
CREATE TABLE IF NOT EXISTS admin_settings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  setting_key TEXT NOT NULL UNIQUE,
  setting_value TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Table: app_logs
CREATE TABLE IF NOT EXISTS app_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  level TEXT NOT NULL CHECK(level IN ('debug','info','warning','error','critical')),
  category TEXT NOT NULL,
  message TEXT NOT NULL,
  user_id INTEGER,
  username TEXT,
  ip_address TEXT,
  user_agent TEXT,
  request_path TEXT,
  session_id TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_level ON app_logs(level);
CREATE INDEX IF NOT EXISTS idx_category ON app_logs(category);
CREATE INDEX IF NOT EXISTS idx_created_at ON app_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_user_id ON app_logs(user_id);

-- Table: app_secrets
CREATE TABLE IF NOT EXISTS app_secrets (
  key_name TEXT PRIMARY KEY,
  secret_value TEXT
);

-- Table: users (must come before password_reset_tokens and stashes due to foreign keys)
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE,
  password TEXT NOT NULL,
  email TEXT UNIQUE,
  is_admin INTEGER DEFAULT 0,
  status TEXT DEFAULT 'approved' CHECK(status IN ('pending','approved')),
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_email ON users(email);

-- Table: password_reset_tokens (references users)
CREATE TABLE IF NOT EXISTS password_reset_tokens (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  token TEXT NOT NULL UNIQUE,
  expires_at TEXT NOT NULL,
  used INTEGER DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_token ON password_reset_tokens(token);
CREATE INDEX IF NOT EXISTS idx_user_id_reset ON password_reset_tokens(user_id);

-- Table: stashes (references users)
CREATE TABLE IF NOT EXISTS stashes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL UNIQUE,
  stash_data TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_user_id_stash ON stashes(user_id);

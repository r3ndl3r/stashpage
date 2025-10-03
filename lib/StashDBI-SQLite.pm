# /lib/StashDBI-SQLite.pm

package StashDBI;
use strict;
use warnings;
use DBI;
use Mojo::JSON qw(decode_json encode_json);
use Crypt::Eksblowfish::Bcrypt qw(bcrypt en_base64);
use Digest::SHA qw(sha256_hex);
use FindBin;
use Exporter qw(import);

# Database interface module for Stashpage application.
# Responsibilities:
# - Provides secure database connection management with environment variable configuration
# - Implements user authentication with bcrypt password hashing and verification
# - Manages user accounts including creation, approval, and administrative functions
# - Handles unified stash data persistence with JSON serialization
# - Provides logging system for security events and application monitoring
# - Implements password reset functionality with secure token management
# - Manages application settings and configuration through database storage
# Integration points:
# - Uses SQLite database with DBI interface for data persistence
# - Integrates with bcrypt for secure password hashing and verification
# - Connects to JSON utilities for stash data serialization and deserialization
# - Supports Docker and environment variable configuration patterns

# Create new database interface instance with environment-based configuration.
# Parameters:
#   $class : Class name for object construction.
#   %args  : Additional configuration arguments (optional).
# Returns:
#   StashDBI instance with established database connection.
sub new {
    my ($class, %args) = @_;
    
    # SQLite: file-based database, no credentials needed
    my $db_file = $ENV{DB_FILE} || "$FindBin::Bin/data/stashpage.db";
    my $dsn = "dbi:SQLite:dbname=$db_file";
    
    print "SQLite DSN: $dsn\n" if $ENV{DEBUG};                     # Debug output for connection troubleshooting
    
    # Connect to SQLite database
    my $dbh = DBI->connect($dsn, "", "", {
        RaiseError => 1,
        PrintError => 0,
        AutoCommit => 1,
        sqlite_unicode => 1,  # Enable UTF-8 support
    }) or die "Cannot connect to SQLite: $DBI::errstr";
    
    # SQLite performance optimizations
    $dbh->do("PRAGMA journal_mode=WAL");        # Write-Ahead Logging for better concurrency
    $dbh->do("PRAGMA busy_timeout=5000");       # Wait 5 seconds if database locked
    $dbh->do("PRAGMA foreign_keys=ON");         # Enforce foreign key constraints
    $dbh->do("PRAGMA synchronous=NORMAL");      # Balance safety and performance
    
    # Create and initialize database interface instance
    my $self = bless {
        dbh => $dbh,
        dsn => $dsn,
        %args
    }, $class;
    
    return $self;
}

# Establish database connection with error handling.
# Parameters:
#   $self : StashDBI instance.
# Returns:
#   None. Sets database handle in instance or dies on failure.
sub connect {
    my ($self) = @_;
    my $db_file = $ENV{DB_FILE} || "$FindBin::Bin/../data/stashpage.db";
    my $dsn = "dbi:SQLite:dbname=$db_file";
    # Create database connection with error handling configuration
    $self->{dbh} = DBI->connect($dsn, "", "", 
        { 
            PrintError => 0,                                 # Disable automatic error printing
            RaiseError => 1,                                 # Enable exception throwing on errors
            sqlite_unicode => 1                              # Enable UTF-8 support
        }) or die $DBI::errstr;
}

# Verify database connection health and reconnect if necessary.
# Parameters:
#   $self : StashDBI instance.
# Returns:
#   None. Reconnects if connection is lost.
sub ensure_connection {
    my ($self) = @_;
    # Test connection with simple query
    eval { $self->{dbh}->do('SELECT 1'); };
    if ($@) {
        # Reconnect if connection test fails
        $self->connect();
    }
}

# Retrieve database handle
sub dbh {
    my ($self) = @_;
    return $self->{dbh};
}

# =============================================================================
# USER MANAGEMENT AND AUTHENTICATION METHODS
# =============================================================================

# Retrieve total count of registered users for statistics.
# Parameters:
#   $self : StashDBI instance.
# Returns:
#   Integer: total number of users in database.
sub get_user_count {
    my ($self) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("SELECT COUNT(*) FROM users");
    $sth->execute();
    my ($count) = $sth->fetchrow_array();
    return $count;
}

# Check if username already exists in database.
# Parameters:
#   $self     : StashDBI instance.
#   $username : Username to check for existence.
# Returns:
#   Boolean: 1 if user exists, 0 if available.
sub user_exists {
    my ($self, $username) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("SELECT COUNT(*) FROM users WHERE username = ?");
    $sth->execute($username);
    my ($count) = $sth->fetchrow_array();
    return $count > 0;
}

# Create new user account with secure password hashing.
# Parameters:
#   $self     : StashDBI instance.
#   $username : New username for account.
#   $password : Plain text password for hashing.
#   $email    : Email address for account.
# Returns:
#   Boolean: 1 on successful creation.
sub create_user {
    my ($self, $username, $password, $email) = @_;
    $self->ensure_connection;
    
    # Determine if this is the first user for automatic admin privileges
    my $is_first_user = $self->get_user_count() <= 1;  # First real user (0 or 1 with demo)
    my $is_admin = $is_first_user ? 1 : 0;                  # Admin flag for first user
    my $status = $is_first_user ? 'approved' : 'pending';   # First user auto-approved

    # Generate secure password hash using bcrypt with random salt
    my $hashed_password;
    eval {
        my $salt = en_base64(join('', map chr(int(rand(256))), 1..16));  # Generate random salt
        $hashed_password = bcrypt($password, '$2a$10$'.$salt);           # Hash with bcrypt
    };
    if ($@) {
        die "Failed to hash password: $@";
    }
    
    # Insert new user record with hashed password and appropriate status
    eval {
        my $sth = $self->{dbh}->prepare("INSERT INTO users (username, password, email, is_admin, status) VALUES (?, ?, ?, ?, ?)");
        $sth->execute($username, $hashed_password, $email, $is_admin, $status);
    };
    if ($@) {
        die "Failed to insert user into database: $@";
    }
    return 1;
}

# Authenticate user credentials against database.
# Parameters:
#   $self     : StashDBI instance.
#   $username : Username for authentication.
#   $password : Plain text password for verification.
# Returns:
#   Integer: 1 for success, 2 for pending approval, 0 for failure.
sub authenticate_user {
    my ($self, $username, $password) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("SELECT password, status FROM users WHERE username = ?");
    $sth->execute($username);
    my $user = $sth->fetchrow_hashref();
    
    return 0 unless $user;                                   # User not found
    return 2 if $user->{status} ne 'approved';              # User pending approval
    
    # Verify password using bcrypt comparison
    my $auth_result = (bcrypt($password, $user->{password}) eq $user->{password}) ? 1 : 0;
    
    return $auth_result;
}

# Approve pending user registration.
# Parameters:
#   $self : StashDBI instance.
#   $id   : User ID to approve.
# Returns:
#   None. Updates user status to approved.
sub approve_user {
    my ($self, $id) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("UPDATE users SET status = 'approved' WHERE id = ?");
    $sth->execute($id);
}

# Retrieve application secret for Mojolicious session security.
# Parameters:
#   $self : StashDBI instance.
# Returns:
#   String: application secret for session encryption.
sub get_app_secret {
    my ($self) = @_;
    $self->ensure_connection();
    
    # Try to retrieve existing secret with key_name 'app_secret'
    my $sth = $self->{dbh}->prepare(
        "SELECT secret_value FROM app_secrets WHERE key_name = 'app_secret' LIMIT 1"
    );
    $sth->execute();
    my ($secret) = $sth->fetchrow_array();
    
    # If no secret exists, generate one automatically
    unless ($secret) {
        print "No app secret found. Generating new secret...\n";
        
        # Generate random secret using Perl (SQLite doesn't have SHA2/UUID/RAND)
        $secret = sha256_hex(rand() . time() . $$ . rand());
        
        my $insert_sth = $self->{dbh}->prepare(
            "INSERT INTO app_secrets (key_name, secret_value) VALUES ('app_secret', ?)"
        );
        $insert_sth->execute($secret);
        
        print "App secret generated successfully!\n";
    }
    
    die "Failed to retrieve or generate application secret\n" unless $secret;
    return $secret;
}

# Check if user has administrative privileges.
# Parameters:
#   $self     : StashDBI instance.
#   $username : Username to check for admin status.
# Returns:
#   Boolean: 1 if user is admin, 0 otherwise.
sub is_admin {
    my ($self, $username) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("SELECT is_admin FROM users WHERE username = ?");
    $sth->execute($username);
    my ($is_admin) = $sth->fetchrow_array();
    return $is_admin ? 1 : 0;
}

# Get numeric user ID from username for database operations.
# Parameters:
#   $self     : StashDBI instance.
#   $username : Username to lookup.
# Returns:
#   Integer: user ID or undef if not found.
sub get_user_id {
    my ($self, $username) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("SELECT id FROM users WHERE username = ?");
    $sth->execute($username);
    my ($id) = $sth->fetchrow_array();
    return $id;
}

# Retrieve user record by username including status.
# Parameters:
#   $self     : StashDBI instance.
#   $username : Username to retrieve.
# Returns:
#   Hashref: user record with id, username, email, is_admin, status or undef if not found.
sub get_user_by_username {
    my ($self, $username) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("SELECT id, username, email, is_admin, status FROM users WHERE username = ?");
    $sth->execute($username);
    return $sth->fetchrow_hashref();
}

# Retrieve all users for administrative management.
# Parameters:
#   $self : StashDBI instance.
# Returns:
#   Arrayref: all user records with profile information.
sub get_all_users {
    my ($self) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("SELECT id, username, email, created_at, is_admin, status FROM users");
    $sth->execute();
    return $sth->fetchall_arrayref({});
}

# Delete user account and associated data.
# Parameters:
#   $self : StashDBI instance.
#   $id   : User ID to delete.
# Returns:
#   None. Removes user record from database.
sub delete_user {
    my ($self, $id) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("DELETE FROM users WHERE id = ?");
    $sth->execute($id);
}

# Retrieve user record by ID for editing.
# Parameters:
#   $self : StashDBI instance.
#   $id   : User ID to retrieve.
# Returns:
#   Hashref: user record or undef if not found.
sub get_user_by_id {
    my ($self, $id) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("SELECT id, username, email, is_admin FROM users WHERE id = ?");
    $sth->execute($id);
    return $sth->fetchrow_hashref();
}

# Update user profile information.
# Parameters:
#   $self     : StashDBI instance.
#   $id       : User ID to update.
#   $username : New username.
#   $email    : New email address.
#   $is_admin : Admin status flag.
# Returns:
#   None. Updates user record in database.
sub update_user {
    my ($self, $id, $username, $email, $is_admin) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("UPDATE users SET username = ?, email = ?, is_admin = ? WHERE id = ?");
    $sth->execute($username, $email, $is_admin, $id);
}

# Update user password with secure hashing.
# Parameters:
#   $self     : StashDBI instance.
#   $id       : User ID to update.
#   $password : New plain text password.
# Returns:
#   None. Updates password hash in database.
sub update_user_password {
    my ($self, $id, $password) = @_;
    $self->ensure_connection;

    # Generate secure password hash using bcrypt
    my $hashed_password;
    eval {
        my $salt = en_base64(join('', map chr(int(rand(256))), 1..16));
        $hashed_password = bcrypt($password, '$2a$10$'.$salt);
    };
    if ($@) {
        die "Failed to hash password: $@";
    }

    # Update password hash in user record
    my $sth = $self->{dbh}->prepare("UPDATE users SET password = ? WHERE id = ?");
    $sth->execute($hashed_password, $id);
}

# =============================================================================
# STASH DATA MANAGEMENT METHODS
# =============================================================================

# Retrieve unified stash data for user dashboard.
# Parameters:
#   $self    : StashDBI instance.
#   $user_id : User ID to retrieve stashes for.
# Returns:
#   Hashref: unified stash structure or empty structure if none exists.
sub get_unified_stashes {
    my ($self, $user_id) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare(
        "SELECT stash_data FROM stashes WHERE user_id = ?"
    );
    $sth->execute($user_id);
    my ($json_data) = $sth->fetchrow_array();
    return $json_data ? decode_json($json_data) : { stashes => {} };  # Return parsed JSON or empty structure
}

# Save unified stash data with JSON serialization.
# Parameters:
#   $self         : StashDBI instance.
#   $user_id      : User ID for data ownership.
#   $unified_data : Unified stash structure to persist.
# Returns:
#   Boolean: success status of save operation.
sub save_unified_stashes {
    my ($self, $user_id, $unified_data) = @_;
    $self->ensure_connection;
    
    # Serialize data to JSON for database storage
    my $json_data = encode_json($unified_data);
    my $sth = $self->{dbh}->prepare(
        "INSERT OR REPLACE INTO stashes (user_id, stash_data, updated_at) 
         VALUES (?, ?, datetime('now'))"
    );
    return $sth->execute($user_id, $json_data);
}

# =============================================================================
# ADMINISTRATIVE SETTINGS METHODS
# =============================================================================

# Retrieve administrative setting value by key.
# Parameters:
#   $self : StashDBI instance.
#   $key  : Setting key to retrieve.
# Returns:
#   String: setting value or undef if not found.
sub get_admin_setting {
    my ($self, $key) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("SELECT setting_value FROM admin_settings WHERE setting_key = ?");
    $sth->execute($key);
    my ($value) = $sth->fetchrow_array();
    return $value;
}

# Store administrative setting with key-value pair.
# Parameters:
#   $self  : StashDBI instance.
#   $key   : Setting key for storage.
#   $value : Setting value to store.
# Returns:
#   Boolean: success status of storage operation.
sub set_admin_setting {
    my ($self, $key, $value) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare(
        "INSERT OR REPLACE INTO admin_settings (setting_key, setting_value, updated_at) 
         VALUES (?, ?, datetime('now'))"
    );
    return $sth->execute($key, $value);
}

# Retrieve Pushover notification settings.
# Parameters:
#   $self : StashDBI instance.
# Returns:
#   Hashref: Pushover configuration with user key and app token.
sub get_pushover_settings {
    my ($self) = @_;
    $self->ensure_connection;
    return {
        user_key => $self->get_admin_setting('pushover_user_key') || '',
        app_token => $self->get_admin_setting('pushover_app_token') || ''
    };
}

# Save Pushover notification configuration.
# Parameters:
#   $self      : StashDBI instance.
#   $user_key  : Pushover user key for notifications.
#   $app_token : Pushover application token.
# Returns:
#   Boolean: success status of save operation.
sub save_pushover_settings {
    my ($self, $user_key, $app_token) = @_;
    $self->ensure_connection;
    $self->set_admin_setting('pushover_user_key', $user_key);
    $self->set_admin_setting('pushover_app_token', $app_token);
    return 1;
}

# =============================================================================
# LOGGING AND MONITORING METHODS
# =============================================================================

# Log application event with comprehensive context information.
# Parameters:
#   $self   : StashDBI instance.
#   %params : Event attributes including level, category, message, and context.
# Returns:
#   Boolean: success status of log insertion.
sub log_event {
    my ($self, %params) = @_;
    $self->ensure_connection;
    
    # Extract event parameters with defaults
    my $level = $params{level} || 'info';                   # Log level (info, warning, error)
    my $category = $params{category} || 'general';          # Event category for filtering
    my $message = $params{message} || '';                   # Event message description
    my $user_id = $params{user_id};                         # User ID if applicable
    my $username = $params{username};                       # Username for quick reference
    my $ip_address = $params{ip_address};                   # Request IP for security tracking
    my $user_agent = $params{user_agent};                   # Browser info for analysis
    my $request_path = $params{request_path};               # Request path for context
    my $session_id = $params{session_id};                   # Session ID for tracking
    
    # Insert comprehensive log record for audit and monitoring
    my $sth = $self->{dbh}->prepare(
        "INSERT INTO app_logs (level, category, message, user_id, username, ip_address, user_agent, request_path, session_id) 
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
    );
    
    return $sth->execute($level, $category, $message, $user_id, $username, $ip_address, $user_agent, $request_path, $session_id);
}

# Count recent failed login attempts for security monitoring.
# Parameters:
#   $self     : StashDBI instance.
#   $username : Username to check for failed attempts.
#   $ip       : IP address to check for failed attempts.
#   $minutes  : Time window in minutes for counting attempts.
# Returns:
#   Integer: count of recent failed login attempts.
sub count_recent_failed_logins {
    my ($self, $username, $ip, $minutes) = @_;
    $self->ensure_connection;
    
    # Count failed authentication attempts within time window
    my $sth = $self->{dbh}->prepare(
        "SELECT COUNT(*) FROM app_logs 
         WHERE category = 'auth' 
         AND level = 'warning' 
         AND message LIKE 'Failed login attempt for user: %' 
         AND (username = ? OR ip_address = ?)
         AND created_at >= datetime('now', '-' || ? || ' minutes')"
    );
    $sth->execute($username, $ip, $minutes);
    my ($count) = $sth->fetchrow_array();
    return $count || 0;
}

# Retrieve recent application logs with filtering support.
# Parameters:
#   $self     : StashDBI instance.
#   $limit    : Maximum number of log entries to return.
#   $level    : Log level filter ('all' for no filtering).
#   $category : Category filter ('all' for no filtering).
# Returns:
#   Arrayref: filtered log entries sorted by creation time.
sub get_recent_logs {
    my ($self, $limit, $level, $category) = @_;
    $self->ensure_connection;
    
    # Build dynamic query with optional filters
    my $sql = "SELECT * FROM app_logs WHERE 1=1";
    my @params;
    
    # Add level filter if specified
    if ($level && $level ne 'all') {
        $sql .= " AND level = ?";
        push @params, $level;
    }
    
    # Add category filter if specified
    if ($category && $category ne 'all') {
        $sql .= " AND category = ?";
        push @params, $category;
    }
    
    # Add ordering and limit
    $sql .= " ORDER BY created_at DESC LIMIT ?";
    push @params, $limit;
    
    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute(@params);
    return $sth->fetchall_arrayref({});
}

# =============================================================================
# EMAIL CONFIGURATION METHODS
# =============================================================================

# Retrieve email SMTP configuration settings.
# Parameters:
#   $self : StashDBI instance.
# Returns:
#   Hashref: email settings with Gmail credentials and sender name.
sub get_email_settings {
    my ($self) = @_;
    $self->ensure_connection;
    return {
        gmail_email => $self->get_admin_setting('gmail_email') || '',
        gmail_app_password => $self->get_admin_setting('gmail_app_password') || '',
        from_name => $self->get_admin_setting('email_from_name') || 'Stashpage'
    };
}

# Save email SMTP configuration settings.
# Parameters:
#   $self               : StashDBI instance.
#   $gmail_email        : Gmail email address for SMTP authentication.
#   $gmail_app_password : Gmail app-specific password.
#   $from_name          : Display name for outgoing emails.
# Returns:
#   Boolean: success status of save operation.
sub save_email_settings {
    my ($self, $gmail_email, $gmail_app_password, $from_name) = @_;
    $self->ensure_connection;
    $self->set_admin_setting('gmail_email', $gmail_email);
    $self->set_admin_setting('gmail_app_password', $gmail_app_password);
    $self->set_admin_setting('email_from_name', $from_name || 'Stashpage');
    return 1;
}

# Retrieve user details by ID for notifications.
# Parameters:
#   $self    : StashDBI instance.
#   $user_id : User ID to retrieve details for.
# Returns:
#   Hashref: user details with ID, username, and email.
sub get_user_details {
    my ($self, $user_id) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("SELECT id, username, email FROM users WHERE id = ?");
    $sth->execute($user_id);
    return $sth->fetchrow_hashref();
}

# =============================================================================
# STATISTICS AND REPORTING METHODS
# =============================================================================

# Retrieve administrative statistics for dashboard display.
# Parameters:
#   $self : StashDBI instance.
# Returns:
#   Hashref: statistics including user counts and stash totals.
sub get_admin_stats {
    my ($self) = @_;
    $self->ensure_connection;
    
    # Get total registered users
    my $sth = $self->{dbh}->prepare("SELECT COUNT(*) FROM users");
    $sth->execute();
    my ($total_users) = $sth->fetchrow_array();
    
    # Get pending approval users
    $sth = $self->{dbh}->prepare("SELECT COUNT(*) FROM users WHERE status = 'pending'");
    $sth->execute();
    my ($pending_users) = $sth->fetchrow_array();
    
    # Count total stashes across all users by parsing JSON data
    $sth = $self->{dbh}->prepare("SELECT stash_data FROM stashes");
    $sth->execute();
    my $all_stashes_data = $sth->fetchall_arrayref();
    
    my $total_stashes = 0;
    # Parse each user's stash JSON to count individual stash pages
    foreach my $row (@$all_stashes_data) {
        my $json_data = $row->[0];
        if ($json_data) {
            # Safely decode JSON and count stash pages
            my $decoded = eval { decode_json($json_data) };
            if (!$@ && $decoded && ref $decoded eq 'HASH' && exists $decoded->{stashes} && ref $decoded->{stashes} eq 'HASH') {
                $total_stashes += scalar(keys %{$decoded->{stashes}});
            }
        }
    }
    
    return {
        total_users => $total_users || 0,
        pending_users => $pending_users || 0,
        total_stashes => $total_stashes
    };
}

# =============================================================================
# PASSWORD RESET FUNCTIONALITY METHODS
# =============================================================================

# Retrieve user record by email for password recovery.
# Parameters:
#   $self  : StashDBI instance.
#   $email : Email address to lookup.
# Returns:
#   Hashref: user record or undef if not found.
sub get_user_by_email {
    my ($self, $email) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("SELECT id, username, email FROM users WHERE email = ? AND status = 'approved'");
    $sth->execute($email);
    return $sth->fetchrow_hashref();
}

# Create secure password reset token with expiration.
# Parameters:
#   $self    : StashDBI instance.
#   $user_id : User ID for password reset.
# Returns:
#   String: secure reset token for email delivery.
sub create_password_reset_token {
    my ($self, $user_id) = @_;
    $self->ensure_connection;
    
    # Generate cryptographically secure random token
    my $token = join('', map { sprintf("%02x", int(rand(256))) } 1..32);
    
    # Set expiration to 30 minutes for security
    my $expires_at = time() + (30 * 60);
    
    # Clean up any existing tokens for this user to prevent abuse
    $self->{dbh}->prepare("DELETE FROM password_reset_tokens WHERE user_id = ?")->execute($user_id);
    
    # Insert new token with expiration timestamp
    my $sth = $self->{dbh}->prepare(
        "INSERT INTO password_reset_tokens (user_id, token, expires_at) VALUES (?, ?, datetime(?, 'unixepoch'))"
    );
    $sth->execute($user_id, $token, $expires_at);
    
    return $token;
}

# Validate password reset token and retrieve user information.
# Parameters:
#   $self  : StashDBI instance.
#   $token : Password reset token to validate.
# Returns:
#   Hashref: user information or undef if token invalid/expired.
sub validate_reset_token {
    my ($self, $token) = @_;
    $self->ensure_connection;
    
    # Verify token exists, is unused, and not expired
    my $sth = $self->{dbh}->prepare(
        "SELECT u.id as user_id, username, email, prt.user_id as token_user_id FROM password_reset_tokens prt 
         JOIN users u ON prt.user_id = u.id 
         WHERE prt.token = ? AND prt.used = 0 AND prt.expires_at > datetime('now')"
    );
    $sth->execute($token);
    my $result = $sth->fetchrow_hashref();
    
    return $result;
}

# Mark password reset token as used to prevent replay attacks.
# Parameters:
#   $self  : StashDBI instance.
#   $token : Password reset token to mark as used.
# Returns:
#   Boolean: success status of token invalidation.
sub use_reset_token {
    my ($self, $token) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("UPDATE password_reset_tokens SET used = 1 WHERE token = ?");
    return $sth->execute($token);
}

# Reset user password with secure hashing.
# Parameters:
#   $self         : StashDBI instance.
#   $user_id      : User ID for password reset.
#   $new_password : New plain text password.
# Returns:
#   Boolean: success status of password update.
sub reset_user_password {
    my ($self, $user_id, $new_password) = @_;
    $self->ensure_connection;
    
    # Generate secure password hash using bcrypt
    my $hashed_password;
    eval {
        my $salt = en_base64(join('', map chr(int(rand(256))), 1..16));
        $hashed_password = bcrypt($new_password, '$2a$10$'.$salt);
    };
    if ($@) {
        die "Failed to hash password: $@";
    }
    
    # Update user password with new hash
    my $sth = $self->{dbh}->prepare("UPDATE users SET password = ? WHERE id = ?");
    my $result = $sth->execute($hashed_password, $user_id);
    
    return $result;
}

# Count recent password reset requests for rate limiting.
# Parameters:
#   $self    : StashDBI instance.
#   $email   : Email address to check for reset requests.
#   $minutes : Time window in minutes for counting requests.
# Returns:
#   Integer: count of recent reset requests.
sub count_recent_reset_requests {
    my ($self, $email, $minutes) = @_;
    $self->ensure_connection;
    
    # Count password reset attempts within time window
    my $sth = $self->{dbh}->prepare(
        "SELECT COUNT(*) FROM password_reset_tokens prt 
         JOIN users u ON prt.user_id = u.id 
         WHERE u.email = ? AND prt.created_at >= datetime('now', '-' || ? || ' minutes')"
    );
    $sth->execute($email, $minutes);
    my ($count) = $sth->fetchrow_array();
    return $count || 0;
}

# Check if email address exists in system.
# Parameters:
#   $self            : StashDBI instance.
#   $email           : Email address to check for existence.
#   $exclude_user_id : (Optional) User ID to exclude from check (for updates).
# Returns:
#   Boolean: 1 if email exists (for another user), 0 if available.
sub email_exists {
    my ($self, $email, $exclude_user_id) = @_;
    $self->ensure_connection;
    
    # If exclude_user_id provided, check for other users with this email
    if (defined $exclude_user_id) {
        my $sth = $self->{dbh}->prepare("SELECT COUNT(*) FROM users WHERE email = ? AND id != ?");
        $sth->execute($email, $exclude_user_id);
        my ($count) = $sth->fetchrow_array();
        return $count > 0;
    }
    
    # Otherwise, check if ANY user has this email (for registration)
    my $sth = $self->{dbh}->prepare("SELECT COUNT(*) FROM users WHERE email = ?");
    $sth->execute($email);
    my ($count) = $sth->fetchrow_array();
    return $count > 0;
}

1;
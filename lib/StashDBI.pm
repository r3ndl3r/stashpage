package StashDBI;
use strict;
use warnings;
use DBI;
use Mojo::JSON qw(decode_json encode_json);
use Crypt::Eksblowfish::Bcrypt qw(bcrypt en_base64);
use Digest::SHA qw(sha256_hex);
use FindBin;
use Exporter qw(import);

# Unified database interface module for the Stashpage application.
# Responsibilities:
# - Provides secure database connection management for MariaDB and SQLite.
# - Implements user authentication with bcrypt password hashing and verification.
# - Manages user accounts including creation, approval, and administrative functions.
# - Handles unified stash data persistence with JSON serialization.
# - Provides a logging system for security events and application monitoring.
# - Implements password reset functionality with secure token management.
# - Manages application settings and configuration through database storage.
# Integration points:
# - Uses DBI interface for data persistence.
# - Integrates with bcrypt for secure password hashing.
# - Connects to JSON utilities for stash data serialization.
# - Supports Docker and environment variable configuration patterns.

# Unified SQL command index, mapping operations to backend-specific SQL statements.
my %SQL_INDEX = (
    insert_user => {
        mariadb => 'INSERT INTO users (username, password, email, is_admin, status) VALUES (?, ?, ?, ?, ?)',
        sqlite  => 'INSERT INTO users (username, password, email, is_admin, status) VALUES (?, ?, ?, ?, ?)',
    },
    upsert_stash => {
        mariadb => 'INSERT INTO stashes (user_id, stash_data) VALUES (?, ?) ON DUPLICATE KEY UPDATE stash_data = VALUES(stash_data)',
        sqlite  => 'INSERT OR REPLACE INTO stashes (user_id, stash_data, updated_at) VALUES (?, ?, datetime("now"))',
    },
    upsert_admin_settings => {
        mariadb => 'INSERT INTO admin_settings (setting_key, setting_value) VALUES (?, ?) ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)',
        sqlite  => 'INSERT OR REPLACE INTO admin_settings (setting_key, setting_value, updated_at) VALUES (?, ?, datetime("now"))',
    },
    password_reset_token => {
        mariadb => 'INSERT INTO password_reset_tokens (user_id, token, expires_at) VALUES (?, ?, FROM_UNIXTIME(?))',
        sqlite  => 'INSERT INTO password_reset_tokens (user_id, token, expires_at) VALUES (?, ?, datetime(?, \'unixepoch\'))',
    },
    valid_reset_token => {
        mariadb => 'SELECT u.id as user_id, username, email FROM password_reset_tokens prt JOIN users u ON prt.user_id = u.id WHERE prt.token = ? AND prt.used = FALSE AND prt.expires_at > NOW()',
        sqlite  => 'SELECT u.id as user_id, username, email FROM password_reset_tokens prt JOIN users u ON prt.user_id = u.id WHERE prt.token = ? AND prt.used = 0 AND prt.expires_at > datetime("now")',
    },
    use_reset_token => {
        mariadb => 'UPDATE password_reset_tokens SET used = TRUE WHERE token = ?',
        sqlite  => 'UPDATE password_reset_tokens SET used = 1 WHERE token = ?',
    },
    count_failed_logins => {
        mariadb => 'SELECT COUNT(*) FROM app_logs WHERE category = \'auth\' AND level = \'warning\' AND message LIKE \'Failed login attempt for user: %\' AND (username = ? OR ip_address = ?) AND created_at >= DATE_SUB(NOW(), INTERVAL ? MINUTE)',
        sqlite  => 'SELECT COUNT(*) FROM app_logs WHERE category = \'auth\' AND level = \'warning\' AND message LIKE \'Failed login attempt for user: %\' AND (username = ? OR ip_address = ?) AND created_at >= datetime(\'now\', \'-\' || ? || \' minutes\')',
    },
    count_reset_requests => {
        mariadb => 'SELECT COUNT(*) FROM password_reset_tokens prt JOIN users u ON prt.user_id = u.id WHERE u.email = ? AND prt.created_at >= DATE_SUB(NOW(), INTERVAL ? MINUTE)',
        sqlite  => 'SELECT COUNT(*) FROM password_reset_tokens prt JOIN users u ON prt.user_id = u.id WHERE u.email = ? AND prt.created_at >= datetime(\'now\', \'-\' || ? || \' minutes\')',
    },
);

# Accessor for backend-specific SQL commands.
sub get_sql {
    my ($self, $operation) = @_;
    return $SQL_INDEX{$operation}{$self->{db_type}};
}

# Create new database interface instance with environment-based configuration.
# Parameters:
#   $class : Class name for object construction.
#   %args  : Configuration arguments including db_type ('sqlite' or 'mariadb').
# Returns:
#   StashDBI instance with an established database connection.
sub new {
    my ($class, %args) = @_;
    my $db_type = $args{db_type} || 'mariadb'; # Default to MariaDB if not specified
    my ($dsn, $dbUser, $dbPass);

    if ($db_type eq 'sqlite') {
        # Configure for SQLite: file-based database
        my $db_file = $ENV{DB_FILE} || "$FindBin::Bin/data/stashpage.db";
        $dsn = "dbi:SQLite:dbname=$db_file";
        $dbUser = ""; # Not required for SQLite
        $dbPass = ""; # Not required for SQLite
    } else { # mariadb
        # Configure for MariaDB: load credentials from environment variables
        $dbUser = $ENV{DB_USER} or die "DB_USER environment variable not set for MariaDB";
        $dbPass = $ENV{DB_PASS} or die "DB_PASS environment variable not set for MariaDB";
        my $db_host = $ENV{DB_HOST} || '127.0.0.1'; # Database host with localhost default
        my $db_name = $ENV{DB_NAME} || 'stashpage'; # Database name with default
        my $db_port = $ENV{DB_PORT} || '3306'; # Port with MySQL/MariaDB default
        $dsn = "dbi:MariaDB:database=$db_name;host=$db_host;port=$db_port";
    }

    print "$db_type DSN: $dsn\n" if $ENV{DEBUG}; # Debug output for connection troubleshooting

    # Create and initialize database interface instance
    my $self = bless {
        dsn      => $dsn,
        dbUser   => $dbUser,
        dbPass   => $dbPass,
        db_type  => $db_type,
        %args
    }, $class;

    $self->connect(); # Establish initial database connection
    return $self;
}

# Establish a database connection.
# Parameters:
#   $self : StashDBI instance.
# Returns:
#   None. Sets database handle in instance or dies on failure.
sub connect {
    my ($self) = @_;
    # Common DBI attributes for error handling and auto-committing
    my %attrs = ( RaiseError => 1, PrintError => 0, AutoCommit => 1 );
    # Add SQLite-specific attribute for UTF-8 support
    $attrs{sqlite_unicode} = 1 if $self->{db_type} eq 'sqlite';

    # Connect to the database or die with an error
    $self->{dbh} = DBI->connect($self->{dsn}, $self->{dbUser}, $self->{dbPass}, \%attrs)
        or die "Cannot connect to database: $DBI::errstr";

    # Apply SQLite-specific performance optimizations after connecting
    if ($self->{db_type} eq 'sqlite') {
        $self->{dbh}->do("PRAGMA journal_mode=WAL");        # Write-Ahead Logging for better concurrency
        $self->{dbh}->do("PRAGMA busy_timeout=5000");       # Wait 5 seconds if database is locked
        $self->{dbh}->do("PRAGMA foreign_keys=ON");         # Enforce foreign key constraints
        $self->{dbh}->do("PRAGMA synchronous=NORMAL");      # Balance safety and performance
    }
}

# Ensure the database connection is active, reconnecting if necessary.
# Parameters:
#   $self : StashDBI instance.
# Returns:
#   None. Reconnects if the connection is lost.
sub ensure_connection {
    my ($self) = @_;
    # Test connection with a simple, low-cost query
    eval { $self->{dbh}->do('SELECT 1'); };
    if ($@) { # If the eval fails ($@ is set)
        $self->connect(); # Re-establish the connection
    }
}

# Retrieve the active database handle.
# Parameters:
#   $self : StashDBI instance.
# Returns:
#   The DBI database handle.
sub dbh {
    my ($self) = @_;
    return $self->{dbh};
}

# =============================================================================
# USER MANAGEMENT AND AUTHENTICATION METHODS
# =============================================================================

# Retrieve the total count of registered users.
# Parameters:
#   $self : StashDBI instance.
# Returns:
#   Integer: The total number of users in the database.
sub get_user_count {
    my ($self) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("SELECT COUNT(*) FROM users");
    $sth->execute();
    my ($count) = $sth->fetchrow_array();
    return $count;
}

# Check if a username already exists.
# Parameters:
#   $self     : StashDBI instance.
#   $username : Username to check.
# Returns:
#   Boolean: 1 if the user exists, 0 otherwise.
sub user_exists {
    my ($self, $username) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("SELECT COUNT(*) FROM users WHERE username = ?");
    $sth->execute($username);
    my ($count) = $sth->fetchrow_array();
    return $count > 0;
}

# Generate cryptographically secure random bytes for password salting.
# Uses /dev/urandom which provides a cryptographically secure pseudorandom
# number generator suitable for all cryptographic purposes including password
# hashing. This replaces the insecure rand() function previously used.
# Parameters:
#   $num_bytes : Number of random bytes to generate.
# Returns:
#   Binary string containing the requested number of random bytes.
sub get_secure_random_bytes {
    my ($num_bytes) = @_;
    
    # Open /dev/urandom in raw binary mode
    open(my $fh, '<:raw', '/dev/urandom') or die "Cannot open /dev/urandom: $!";
    
    # Read the requested number of random bytes
    my $bytes;
    my $bytes_read = read($fh, $bytes, $num_bytes);
    close($fh);
    
    # Verify we got the right number of bytes
    die "Failed to read $num_bytes bytes from /dev/urandom (got $bytes_read)" 
        unless $bytes_read == $num_bytes;
    
    return $bytes;
}

# Generate a properly formatted bcrypt salt for password hashing.
# Bcrypt requires exactly 22 characters from its specific base64 alphabet.
# This function generates cryptographically secure random bytes, encodes them
# using bcrypt's base64 encoding, removes any padding characters that would
# cause "bad bcrypt settings" errors, and truncates to the required length.
# Parameters:
#   None.
# Returns:
#   String: A 22-character bcrypt-compatible salt string.
sub generate_bcrypt_salt {
    return get_secure_random_bytes(16);
}

# Create a new user account with a securely hashed password.
# Parameters:
#   $self     : StashDBI instance.
#   $username : New username for the account.
#   $password : Plain text password to be hashed.
#   $email    : Email address for the account.
# Returns:
#   Boolean: 1 on successful creation.
sub create_user {
    my ($self, $username, $password, $email) = @_;
    $self->ensure_connection;

    # Check if any admin user already exists to determine if this new user should be an admin
    my $admin_sth = $self->{dbh}->prepare("SELECT COUNT(*) FROM users WHERE is_admin = 1");
    $admin_sth->execute();
    my ($admin_count) = $admin_sth->fetchrow_array();
    
    # The first user registered becomes an administrator automatically
    my $is_admin = ($admin_count == 0) ? 1 : 0; # Admin flag for the first user
    my $status = $is_admin ? 'approved' : 'pending'; # First user is auto-approved

    # Generate a random salt and hash the password using bcrypt
    my $salt = get_secure_random_bytes(16);
    my $salt_encoded = en_base64($salt);
    my $hashed_password = bcrypt($password, '$2a$10$' . $salt_encoded);

    # Insert the new user record into the database
    my $sth = $self->{dbh}->prepare($self->get_sql('insert_user'));
    $sth->execute($username, $hashed_password, $email, $is_admin, $status);
    return 1; # Return success
}

# Create a demo user account.
# Parameters:
#   $self     : StashDBI instance.
#   $username : Demo username.
#   $password : Plain text password.
#   $email    : Email for the demo account.
# Returns:
#   Boolean: 1 on successful creation.
sub create_demo_user {
    my ($self, $username, $password, $email) = @_;
    $self->ensure_connection;

    my $is_admin = 0;       # Demo user is never an administrator
    my $status = 'pending'; # Demo user always requires manual approval

    # Generate a random salt and hash the password using bcrypt
    my $salt = get_secure_random_bytes(16);
    my $salt_encoded = en_base64($salt);
    my $hashed_password = bcrypt($password, '$2a$10$' . $salt_encoded);

    # Insert the demo user record
    my $sth = $self->{dbh}->prepare($self->get_sql('insert_user'));
    $sth->execute($username, $hashed_password, $email, $is_admin, $status);
    return 1; # Return success
}

# Authenticate a user against their stored credentials.
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


    return 0 unless $user; # User not found
    return 2 if $user->{status} ne 'approved'; # User is pending approval


    # Verify password using bcrypt comparison
    return (bcrypt($password, $user->{password}) eq $user->{password}) ? 1 : 0;
}

# Approve a pending user registration.
# Parameters:
#   $self : StashDBI instance.
#   $id   : User ID to approve.
# Returns:
#   None. Updates the user's status to 'approved'.
sub approve_user {
    my ($self, $id) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("UPDATE users SET status = 'approved' WHERE id = ?");
    $sth->execute($id);
}

# Retrieve the application secret for session security.
# Parameters:
#   $self : StashDBI instance.
# Returns:
#   String: The application secret for session encryption.
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
        
        if ($self->{db_type} eq 'sqlite') {
            # SQLite: Generate secret in Perl since SQLite lacks SHA2/UUID/RAND
            $secret = sha256_hex(rand() . time() . $$ . rand());
            
            my $insert_sth = $self->{dbh}->prepare(
                "INSERT INTO app_secrets (key_name, secret_value) VALUES ('app_secret', ?)"
            );
            $insert_sth->execute($secret);
        } else {
            # MariaDB: Use database functions for secret generation
            my $insert_sth = $self->{dbh}->prepare(
                "INSERT INTO app_secrets (key_name, secret_value) 
                 VALUES ('app_secret', SHA2(CONCAT(RAND(), UUID(), NOW()), 256))"
            );
            $insert_sth->execute();
            
            # Retrieve the newly created secret
            $sth->execute();
            ($secret) = $sth->fetchrow_array();
        }
        
        print "App secret generated successfully!\n";
    }
    
    die "Failed to retrieve or generate application secret\n" unless $secret;
    return $secret;
}

# Check if a user has administrative privileges.
# Parameters:
#   $self     : StashDBI instance.
#   $username : Username to check.
# Returns:
#   Boolean: 1 if the user is an admin, 0 otherwise.
sub is_admin {
    my ($self, $username) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("SELECT is_admin FROM users WHERE username = ?");
    $sth->execute($username);
    my ($is_admin) = $sth->fetchrow_array();
    return $is_admin ? 1 : 0;
}

# Get a numeric user ID from a username.
# Parameters:
#   $self     : StashDBI instance.
#   $username : Username to look up.
# Returns:
#   Integer: The user's ID, or undef if not found.
sub get_user_id {
    my ($self, $username) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("SELECT id FROM users WHERE username = ?");
    $sth->execute($username);
    my ($id) = $sth->fetchrow_array();
    return $id;
}

# Retrieve a user record by username.
# Parameters:
#   $self     : StashDBI instance.
#   $username : Username to retrieve.
# Returns:
#   Hashref: The user record, or undef if not found.
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
#   Arrayref of hashrefs: A list of all user records.
sub get_all_users {
    my ($self) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("SELECT id, username, email, created_at, is_admin, status FROM users");
    $sth->execute();
    return $sth->fetchall_arrayref({});
}

# Delete a user account and associated data.
# Parameters:
#   $self : StashDBI instance.
#   $id   : User ID to delete.
# Returns:
#   None. Removes the user record from the database.
sub delete_user {
    my ($self, $id) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("DELETE FROM users WHERE id = ?");
    $sth->execute($id);
}

# Retrieve a user record by ID.
# Parameters:
#   $self : StashDBI instance.
#   $id   : User ID to retrieve.
# Returns:
#   Hashref: The user record, or undef if not found.
sub get_user_by_id {
    my ($self, $id) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("SELECT id, username, email, is_admin FROM users WHERE id = ?");
    $sth->execute($id);
    return $sth->fetchrow_hashref();
}

# Update a user's profile information.
# Parameters:
#   $self     : StashDBI instance.
#   $id       : User ID to update.
#   $username : New username.
#   $email    : New email address.
#   $is_admin : Admin status flag (1 or 0).
# Returns:
#   None. Updates the user record in the database.
sub update_user {
    my ($self, $id, $username, $email, $is_admin) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("UPDATE users SET username = ?, email = ?, is_admin = ? WHERE id = ?");
    $sth->execute($username, $email, $is_admin, $id);
}

# Update a user's password with a new securely hashed password.
# Parameters:
#   $self     : StashDBI instance.
#   $id       : User ID to update.
#   $password : New plain text password.
# Returns:
#   None. Updates the password hash in the database.
sub update_user_password {
    my ($self, $id, $password) = @_;
    $self->ensure_connection;

    # Generate a new random salt and hash the password
    my $salt = get_secure_random_bytes(16);
    my $salt_encoded = en_base64($salt);
    my $hashed_password = bcrypt($password, '$2a$10$' . $salt_encoded);

    # Update the user's password in the database
    my $sth = $self->{dbh}->prepare("UPDATE users SET password = ? WHERE id = ?");
    $sth->execute($hashed_password, $id);
}

# =============================================================================
# STASH DATA MANAGEMENT METHODS
# =============================================================================

# Retrieve the unified stash data for a user.
# Parameters:
#   $self    : StashDBI instance.
#   $user_id : User ID to retrieve stashes for.
# Returns:
#   Hashref: The unified stash structure, or an empty structure if none exists.
sub get_unified_stashes {
    my ($self, $user_id) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("SELECT stash_data FROM stashes WHERE user_id = ?");
    $sth->execute($user_id);
    my ($json_data) = $sth->fetchrow_array();
    # Decode the JSON string from the database into a Perl hash reference
    return $json_data ? decode_json($json_data) : { stashes => {} }; # Return parsed JSON or an empty structure
}

# Save the unified stash data with JSON serialization.
# Parameters:
#   $self         : StashDBI instance.
#   $user_id      : User ID for data ownership.
#   $unified_data : The unified stash structure to persist.
# Returns:
#   Boolean: Success status of the save operation.
sub save_unified_stashes {
    my ($self, $user_id, $unified_data) = @_;
    $self->ensure_connection;
    # Encode the Perl hash reference into a JSON string for storage
    my $json_data = encode_json($unified_data);


    my $sth = $self->{dbh}->prepare($self->get_sql('upsert_stash'));
    return $sth->execute($user_id, $json_data);
}

# =============================================================================
# ADMINISTRATIVE SETTINGS METHODS
# =============================================================================

# Retrieve an administrative setting value by its key.
# Parameters:
#   $self : StashDBI instance.
#   $key  : The setting key to retrieve.
# Returns:
#   String: The setting value, or undef if not found.
sub get_admin_setting {
    my ($self, $key) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("SELECT setting_value FROM admin_settings WHERE setting_key = ?");
    $sth->execute($key);
    my ($value) = $sth->fetchrow_array();
    return $value;
}

# Store an administrative setting as a key-value pair.
# Parameters:
#   $self  : StashDBI instance.
#   $key   : The setting key for storage.
#   $value : The setting value to store.
# Returns:
#   Boolean: Success status of the storage operation.
sub set_admin_setting {
    my ($self, $key, $value) = @_;
    $self->ensure_connection;


    my $sth = $self->{dbh}->prepare($self->get_sql('upsert_admin_settings'));
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
#   Boolean: 1 (success).
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


# Log an application event with comprehensive context information.
# Parameters:
#   $self   : StashDBI instance.
#   %params : Event attributes including level, category, message, and context.
# Returns:
#   Boolean: Success status of the log insertion.
sub log_event {
    my ($self, %params) = @_;
    $self->ensure_connection;


    my $sth = $self->{dbh}->prepare(
        "INSERT INTO app_logs (level, category, message, user_id, username, ip_address, user_agent, request_path, session_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
    );

    # Execute the insert with provided parameters, using defaults for any that are missing
    return $sth->execute(
        $params{level} || 'info',          # Log level (info, warning, error)
        $params{category} || 'general',    # Event category for filtering
        $params{message} || '',            # Event message description
        $params{user_id},                  # User ID if applicable
        $params{username},                 # Username for quick reference
        $params{ip_address},               # Request IP for security tracking
        $params{user_agent},               # Browser info for analysis
        $params{request_path},             # Request path for context
        $params{session_id}                # Session ID for tracking
    );
}

# Count recent failed login attempts for security monitoring.
# Parameters:
#   $self     : StashDBI instance.
#   $username : Username to check for failed attempts.
#   $ip       : IP address to check for failed attempts.
#   $minutes  : Time window in minutes for counting attempts.
# Returns:
#   Integer: The count of recent failed login attempts.
sub count_recent_failed_logins {
    my ($self, $username, $ip, $minutes) = @_;
    $self->ensure_connection;


    my $sth = $self->{dbh}->prepare($self->get_sql('count_failed_logins'));
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
#   Arrayref of hashrefs: The filtered log entries.
sub get_recent_logs {
    my ($self, $limit, $level, $category) = @_;
    $self->ensure_connection;

    # Build the base SQL query
    my $sql = "SELECT * FROM app_logs WHERE 1=1";
    my @params;

    # Dynamically add filters to the query if they are provided
    if ($level && $level ne 'all') {
        $sql .= " AND level = ?";
        push @params, $level;
    }
    if ($category && $category ne 'all') {
        $sql .= " AND category = ?";
        push @params, $category;
    }

    # Add ordering and limit to the query
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
#   Hashref: Email settings with Gmail credentials and sender name.
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
#   $gmail_email        : Gmail email address.
#   $gmail_app_password : Gmail app-specific password.
#   $from_name          : Display name for outgoing emails.
# Returns:
#   Boolean: 1 (success).
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
#   Hashref: User details including ID, username, and email.
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

# Retrieve administrative statistics.
# Parameters:
#   $self : StashDBI instance.
# Returns:
#   Hashref: Statistics including user counts and stash totals.
sub get_admin_stats {
    my ($self) = @_;
    $self->ensure_connection;


    # Get total registered users
    my $sth_total_users = $self->{dbh}->prepare("SELECT COUNT(*) FROM users");
    $sth_total_users->execute();
    my ($total_users) = $sth_total_users->fetchrow_array();


    # Get count of users pending approval
    my $sth_pending_users = $self->{dbh}->prepare("SELECT COUNT(*) FROM users WHERE status = 'pending'");
    $sth_pending_users->execute();
    my ($pending_users) = $sth_pending_users->fetchrow_array();


    # Get all stash data to calculate total stashes
    my $sth_stashes = $self->{dbh}->prepare("SELECT stash_data FROM stashes");
    $sth_stashes->execute();
    my $all_stashes_data = $sth_stashes->fetchall_arrayref();


    my $total_stashes = 0;
    # Iterate through each user's stash data to count their stash pages
    foreach my $row (@$all_stashes_data) {
        my $json_data = $row->[0];
        if ($json_data) {
            # Safely decode the JSON and count the stash pages
            my $decoded = eval { decode_json($json_data) };
            if (!$@ && ref($decoded) eq 'HASH' && exists $decoded->{stashes} && ref($decoded->{stashes}) eq 'HASH') {
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

# Retrieve a user record by email for password recovery.
# Parameters:
#   $self  : StashDBI instance.
#   $email : Email address to look up.
# Returns:
#   Hashref: The user record, or undef if not found.
sub get_user_by_email {
    my ($self, $email) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare("SELECT id, username, email FROM users WHERE email = ? AND status = 'approved'");
    $sth->execute($email);
    return $sth->fetchrow_hashref();
}

# Create a secure password reset token with an expiration.
# Parameters:
#   $self    : StashDBI instance.
#   $user_id : User ID for whom the token is generated.
# Returns:
#   String: The secure reset token.
sub create_password_reset_token {
    my ($self, $user_id) = @_;
    $self->ensure_connection;

    # Generate a cryptographically secure random token
    my $token = unpack('H*', get_secure_random_bytes(32));
    my $expires_at = time() + (30 * 60); # Token expires in 30 minutes

    # Clean up any existing tokens for this user to prevent abuse
    $self->{dbh}->prepare("DELETE FROM password_reset_tokens WHERE user_id = ?")->execute($user_id);
    
    my $sth = $self->{dbh}->prepare($self->get_sql('password_reset_token'));
    $sth->execute($user_id, $token, $expires_at);

    return $token;
}

# Validate a password reset token.
# Parameters:
#   $self  : StashDBI instance.
#   $token : The password reset token to validate.
# Returns:
#   Hashref: User information if the token is valid and not expired, otherwise undef.
sub validate_reset_token {
    my ($self, $token) = @_;
    $self->ensure_connection;

    my $sth = $self->{dbh}->prepare($self->get_sql('valid_reset_token'));
    $sth->execute($token);
    return $sth->fetchrow_hashref();
}

# Mark a password reset token as used to prevent replay attacks.
# Parameters:
#   $self  : StashDBI instance.
#   $token : The token to invalidate.
# Returns:
#   Boolean: Success status of the token invalidation.
sub use_reset_token {
    my ($self, $token) = @_;
    $self->ensure_connection;
    my $sth = $self->{dbh}->prepare($self->get_sql('use_reset_token'));
    return $sth->execute($token);
}

# Reset a user's password with a new securely hashed password.
# Parameters:
#   $self         : StashDBI instance.
#   $user_id      : The user ID for the password reset.
#   $new_password : The new plain text password.
# Returns:
#   Boolean: Success status of the password update.
sub reset_user_password {
    my ($self, $user_id, $new_password) = @_;
    $self->ensure_connection;
    
    # Generate a new salt and hash the new password
    my $salt = get_secure_random_bytes(16);
    my $salt_encoded = en_base64($salt);
    my $hashed_password = bcrypt($new_password, '$2a$10$' . $salt_encoded);

    # Update the user's password in the database
    my $sth = $self->{dbh}->prepare("UPDATE users SET password = ? WHERE id = ?");
    return $sth->execute($hashed_password, $user_id);
}

# Count recent password reset requests for rate limiting.
# Parameters:
#   $self    : StashDBI instance.
#   $email   : Email address to check for reset requests.
#   $minutes : Time window in minutes for counting requests.
# Returns:
#   Integer: The count of recent reset requests.
sub count_recent_reset_requests {
    my ($self, $email, $minutes) = @_;
    $self->ensure_connection;

    my $sth = $self->{dbh}->prepare($self->get_sql('count_reset_requests'));
    $sth->execute($email, $minutes);
    my ($count) = $sth->fetchrow_array();
    return $count || 0;
}

# Check if an email address already exists in the system.
# Parameters:
#   $self            : StashDBI instance.
#   $email           : Email address to check.
#   $exclude_user_id : (Optional) A user ID to exclude from the check.
# Returns:
#   Boolean: 1 if the email exists for another user, 0 otherwise.
sub email_exists {
    my ($self, $email, $exclude_user_id) = @_;
    $self->ensure_connection;
    
    my $sql = "SELECT COUNT(*) FROM users WHERE email = ?";
    my @params = ($email);

    # If excluding a user ID (e.g., when a user is updating their own email), add it to the query
    if (defined $exclude_user_id) {
        $sql .= " AND id != ?";
        push @params, $exclude_user_id;
    }
    
    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute(@params);
    my ($count) = $sth->fetchrow_array();
    return $count > 0;
}

1;

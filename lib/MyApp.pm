# /lib/MyApp.pm
package MyApp;
use Mojo::Base 'Mojolicious';
use strict;
use warnings;
use FindBin;
use StashDBI;

# Application root class for Stashpage.
# Responsibilities:
#   - Initialize configuration, database, sessions, plugins, and routes during application startup.
#   - Expose helpers and hooks required by downstream controllers and plugins.
# Dependencies:
#   - StashDBI must provide get_app_secret and database connectivity methods.
#   - MyApp::Routes must provide setup_routes($app).

sub startup {
    my $self = shift;

    # Entry point called once at application start.
    # Side effects:
    #   - Sets run mode, loads configuration, initializes DB and sessions,
    #     loads required plugins, and registers HTTP routes.
    # Parameters:
    #   - $self: Mojolicious application instance.
    # Returns:
    #   - Undefined; configures $self in place.
    $self->mode('development');
    $self->_setup_config();
    $self->_setup_database();
    $self->_setup_sessions();
    $self->_load_plugins();
    $self->_setup_routes();
}


sub _setup_config {
    my $self        = shift;
    my $config_file = "$FindBin::Bin/stashpage.conf";

    # Loads configuration from a static filesystem path into $self->config.
    # Notes:
    #   - The path is static; changes require redeploy or code update.
    #   - The Config plugin merges values into $self->config for global access.
    # Parameters:
    #   - $self: Mojolicious application instance.
    # Returns:
    #   - The configuration hashref from the plugin (assigned but not used directly).
    
    # Use default config if file doesn't exist
    my $config = -f $config_file 
        ? $self->plugin('Config' => { file => $config_file })
        : $self->plugin('Config' => { default => {} });
}


sub _setup_database {
    my $self = shift;

    # Initializes the database integration and session signing secret.
    # Responsibilities:
    #   - Load appropriate database driver based on DB_TYPE environment variable.
    #   - Initialize SQLite database if it doesn't exist.
    #   - Fetch a secret from the database for cookie/session signing.
    #   - Register a reusable 'db' helper for controllers and plugins.
    #   - Ensure DB connections are re-established after process fork.
    # Parameters:
    #   - $self: Mojolicious application instance.
    # Returns:
    #   - Undefined; mutates application state.
    
    # Check DB_TYPE environment variable (defaults to 'mariadb')
    my $db_type = $ENV{DB_TYPE} || 'mariadb';
    print "Initializing database driver: $db_type\n" if $ENV{DEBUG};
    
    # SQLite-specific: check if database needs initialization
    if ($db_type eq 'sqlite') {
        my $db_file = $ENV{DB_FILE} || "$FindBin::Bin/data/stashpage.db";
        
        # Check if database file doesn't exist OR is empty (no tables)
        my $needs_init = 0;
        
        if (!-f $db_file) {
            $needs_init = 1;
        } else {
            # Check if database has tables
            require DBI;
            my $check_dbh = DBI->connect("dbi:SQLite:dbname=$db_file", "", "", {
                RaiseError => 0,
                PrintError => 0,
            });
            if ($check_dbh) {
                my $tables = $check_dbh->selectall_arrayref(
                    "SELECT name FROM sqlite_master WHERE type='table'"
                );
                $needs_init = 1 if (!$tables || @$tables == 0);
                $check_dbh->disconnect;
            }
        }
        
        if ($needs_init) {
            print "SQLite database needs initialization at: $db_file\n";
            print "Creating new database and initializing schema...\n";
            $self->_initialize_sqlite_database($db_file);
        }
        
        # Load SQLite driver (can't use 'use' due to hyphen in filename)
        require "$FindBin::Bin/lib/StashDBI-SQLite.pm";
    }
    
    my $db = StashDBI->new();
    my $secret = $db->get_app_secret();
    $self->secrets([$secret]);

    # Expose a persistent DB handle via helper for controllers/views/plugins.
    $self->helper(db => sub {
        state $db = StashDBI->new;
        return $db;
    });

    # Reconnect the DB after prefork/server worker fork events.
    $self->hook(after_fork => sub {
        shift->helper('db')->connect;
    });
}

# Initialize SQLite database on first run.
# Parameters:
#   $self    : MyApp instance.
#   $db_file : Path to SQLite database file.
# Returns:
#   None. Creates database file and schema.
sub _initialize_sqlite_database {
    my ($self, $db_file) = @_;
    
    # Create directory if it doesn't exist
    use File::Basename;
    use File::Path qw(make_path);
    my $db_dir = dirname($db_file);
    make_path($db_dir) unless -d $db_dir;
    
    # Read schema file
    my $schema_file = "$FindBin::Bin/database/schema_sqlite.sql";
    
    unless (-f $schema_file) {
        die "Schema file not found: $schema_file\n";
    }
    
    print "Creating database schema from: $schema_file\n";
    
    # Use sqlite3 command to load schema (preserves order)
    my $result = system("sqlite3 '$db_file' < '$schema_file'");
    
    if ($result != 0) {
        die "Failed to initialize SQLite database\n";
    }
    
    print "SQLite database initialized successfully at: $db_file\n";
}

sub _setup_sessions {
    my $self = shift;

    # Configures session cookie behavior for the application.
    # Parameters:
    #   - $self: Mojolicious application instance.
    # Behavior:
    #   - Sets a stable cookie name and a 30-day default expiration.
    # Returns:
    #   - Undefined; updates session configuration.
    $self->sessions->cookie_name('stash_session');
    $self->sessions->default_expiration(3600 * 24 * 30);  # 30 days
}


sub _load_plugins {
    my $self = shift;

    # Loads required plugins and passes operational configuration.
    # Plugins:
    #   - MyApp::Plugin::Stash: stash page layout defaults and validation.
    #   - MyApp::Plugin::Email: SMTP transport and delivery controls.
    #   - MyApp::Plugin::Core: alert rendering, event logging, notifications.
    #   - MyApp::Plugin::Auth: authentication policies and notifications.
    # Returns:
    #   - Undefined; registers plugin-provided helpers and hooks.
    $self->plugin('MyApp::Plugin::Stash', {
        default_position_x         => 50,
        default_position_y         => 50,
        max_categories_per_page    => 50,
        enable_position_validation => 1
    });

    $self->plugin('MyApp::Plugin::Email', {
        smtp_timeout => 30,
        smtp_host    => 'smtp.gmail.com',
        smtp_port    => 587,
        debug_email  => 0
    });

    $self->plugin('MyApp::Plugin::Core', {
        pushover_timeout     => 30,
        default_alert_status => 400,
        log_user_agents      => 1
    });

    $self->plugin('MyApp::Plugin::Auth', {
        failed_login_threshold => 3,
        failed_login_window    => 15,
        notifications_enabled  => 1
    });
}


sub _setup_routes {
    my $self = shift;

    # Loads and registers the HTTP routes for all controllers.
    # Parameters:
    #   - $self: Mojolicious application instance.
    # Integration:
    #   - Requires MyApp::Routes to implement setup_routes($app).
    # Returns:
    #   - Undefined; registers routes on the app router.
    require MyApp::Routes;
    MyApp::Routes::setup_routes($self);
}

1;

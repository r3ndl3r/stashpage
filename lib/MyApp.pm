# /lib/MyApp.pm
package MyApp;
use Mojo::Base 'Mojolicious';
use strict;
use warnings;
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
    my $self = shift;

    # Loads configuration from a static filesystem path into $self->config.
    # Notes:
    #   - The path is static; changes require redeploy or code update.
    #   - The Config plugin merges values into $self->config for global access.
    # Parameters:
    #   - $self: Mojolicious application instance.
    # Returns:
    #   - The configuration hashref from the plugin (assigned but not used directly).
    my $config = $self->plugin('Config' => {
        file => "$ENV{HOME}/stashpage/stashpage.conf"
    });
}


sub _setup_database {
    my $self = shift;

    # Initializes the database integration and session signing secret.
    # Responsibilities:
    #   - Fetch a secret from the database for cookie/session signing.
    #   - Register a reusable 'db' helper for controllers and plugins.
    #   - Ensure DB connections are re-established after process fork.
    # Parameters:
    #   - $self: Mojolicious application instance.
    # Returns:
    #   - Undefined; mutates application state.
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

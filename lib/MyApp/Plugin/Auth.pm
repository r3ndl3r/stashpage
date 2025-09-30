# /lib/MyApp/Plugin/Auth.pm

package MyApp::Plugin::Auth;

use Mojo::Base 'Mojolicious::Plugin', -signatures;
use strict;
use warnings;

# Authentication and authorization plugin for stash management application.
# Responsibilities:
# - Provides user session management and authentication status checking
# - Implements admin privilege verification with database integration
# - Monitors failed login attempts with configurable security thresholds
# - Sends automatic security notifications via Pushover integration
# - Enforces route-level access control through middleware hooks
# Integration points:
# - Uses DB helpers for user authentication and privilege checking
# - Integrates with Pushover notification service for security alerts
# - Utilizes logging system for comprehensive security audit trail

# Register authentication helpers and middleware with the application.
# Parameters:
#   $self   : Instance of plugin.
#   $app    : Mojolicious app object.
#   $config : Hashref of configuration overrides (optional).
# Returns:
#   None. Registers helpers and hooks in $app.
sub register ($self, $app, $config = {}) {
    # Configuration defaults for security thresholds and notification settings
    my $failed_login_threshold = $config->{failed_login_threshold} || 3;    # Max failed attempts before alert
    my $failed_login_window = $config->{failed_login_window} || 15;         # Time window in minutes
    my $notifications_enabled = $config->{notifications_enabled} // 1;     # Enable security notifications
    
    # Helper: is_logged_in
    # Checks if user has active authenticated session.
    # Parameters:
    #   $c : Mojolicious controller (calling context).
    # Returns:
    #   Boolean: 1 if authenticated session exists, 0 otherwise.
    $app->helper(is_logged_in => sub ($c) { 
        my $user = $c->session('user');                 # Session username
        return defined $user && length($user) ? 1 : 0; # Validate session presence
    });

    # Helper: is_admin
    # Verifies administrative privileges for current user.
    # Parameters:
    #   $c : Mojolicious controller (calling context).
    # Returns:
    #   Boolean: 1 for admin users, 0 for regular users or unauthenticated.
    $app->helper(is_admin => sub ($c) {
        # Require authenticated session before checking admin status
        return 0 unless $c->session('user');
        
        # Integration: DB helper for real-time privilege verification
        return $c->db->is_admin($c->session('user'));  # DB: check admin flag
    });

    # Helper: current_user_id
    # Retrieves numeric user ID for database operations.
    # Parameters:
    #   $c : Mojolicious controller (calling context).
    # Returns:
    #   Integer: user ID or 0 if no valid session.
    $app->helper(current_user_id => sub ($c) { 
        my $username = $c->session('user') // '';      # Current session username
        return 0 unless length($username);
        
        # Integration: DB helper for username to ID conversion
        return $c->db->get_user_id($username);         # DB: convert username to ID
    });

    # Helper: check_failed_logins
    # Monitors failed login attempts and triggers security alerts.
    # Parameters:
    #   $c        : Mojolicious controller (calling context).
    #   $username : Username from failed login attempt.
    #   $ip       : IP address of failed login attempt.
    # Returns:
    #   Integer: count of recent failed attempts.
    $app->helper(check_failed_logins => sub ($c, $username, $ip) {
        # Query recent failed attempts within configured time window
        my $recent_failures = $c->db->count_recent_failed_logins(  # DB: count failed attempts
            $username, 
            $ip, 
            $failed_login_window
        );
        
        # Send security alert if threshold exceeded and notifications enabled
        if ($recent_failures >= $failed_login_threshold && $notifications_enabled) {
            eval {
                # Integration: Pushover helper for security notifications
                $c->send_pushover(
                    "Multiple failed login attempts detected:\n" .
                    "Username: $username\n" .
                    "IP Address: $ip\n" .
                    "Attempt Count: $recent_failures\n" .
                    "Time Window: $failed_login_window minutes",
                    "Security Alert - Failed Login Attempts"
                );
            };
            
            # Log notification failures for troubleshooting
            if ($@) {
                $c->log_event(
                    level => 'warning',
                    category => 'admin',
                    message => "Failed to send Pushover security notification: $@"
                );
            }
        }
        
        return $recent_failures;                       # Return count for caller processing
    });

    # Hook: before_routes
    # Enforces authentication and authorization requirements.
    # Executes before each route to provide centralized access control.
    $app->hook(before_routes => sub ($c) {
        my $path = $c->req->url->path->to_string;      # Current request path
        
        # Allow unrestricted access to authentication endpoints
        return if $path =~ m{^/(login|register|forgot-password|reset-password)/?$};
        
        # Allow access to static resources and public APIs
        return if $path =~ m{^/(css|js|img|favicon)/} || $path =~ m{^/api/public/};
        
        # Enforce authentication and authorization for admin routes
        if ($path =~ m{^/admin}) {
            # Redirect unauthenticated users to login with return path
            unless ($c->is_logged_in) {
                my $return_url = $c->url_for($path)->query($c->req->url->query);
                return $c->redirect_to("/login?return=" . $c->url_escape($return_url));
            }
            
            # Deny access to non-admin users with security logging
            unless ($c->is_admin) {
                $c->log_event(
                    level => 'warning',
                    category => 'security',
                    message => "Non-admin user attempted admin access: " . $c->session('user')
                );
                return $c->alert('Access denied - Administrator privileges required', 403);
            }
        }
    });
}


1;

# /lib/MyApp/Controller/Admin/System.pm

package MyApp::Controller::Admin::System;

use Mojo::Base 'Mojolicious::Controller', -signatures;

# Controller for administrative system operations and monitoring.
# Responsibilities:
# - Provides admin dashboard with system statistics and overview
# - Handles application restart functionality with process management
# - Displays system logs with filtering and pagination capabilities
# - Enforces administrative access control on all system operations
# Integration points:
# - Uses authentication helpers (is_logged_in, is_admin) for security
# - Integrates with DB helpers for statistics and log retrieval
# - Depends on Hypnotoad process manager for application restarts
# - Utilizes fork() for non-blocking restart operations

# Display admin dashboard with system statistics overview.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Redirect to login if not authenticated, alert on access denied, admin dashboard render on success.
sub index ($c) {
    # Enforce user authentication for admin dashboard access
    return $c->redirect_to('/login') unless $c->is_logged_in;
    # Enforce administrator privileges for system statistics
    return $c->alert('Access denied. You must be an administrator to view this page.', 403) unless $c->is_admin;

    # Retrieve system statistics from database for dashboard display
    my $stats = $c->db->get_admin_stats();  # DB: fetch system metrics and counts

    # Render admin dashboard with statistics data
    $c->render('admin/index', stats => $stats);
}


# Handle application restart functionality with process forking.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Redirect to login if not authenticated, alert on access denied, form render or restart confirmation.
sub restart ($c) {
    # Enforce user authentication for restart operations
    return $c->redirect_to('/login') unless $c->is_logged_in;
    # Enforce administrator privileges for system restart
    return $c->alert('Access denied. You must be an administrator to view this page.', 403) unless $c->is_admin;

    if ($c->req->method eq 'POST') {
        # Fork process to prevent blocking the web response
        my $pid = fork();                    # Create child process for restart operation
        my $base_path = $c->app->home;       # Application home directory for command execution

        if ($pid == 0) {
            # Child process: execute restart command sequence
            my $cmd = "cd $base_path && hypnotoad -s stashpage.pl && hypnotoad stashpage.pl";  # Stop and start Hypnotoad server
            exec('sh', '-c', $cmd) or die "Failed to execute shell command: $!";
        } elsif ($pid > 0) {
            # Parent process: notify user and redirect
            $c->flash(message => 'Service restart command initiated.');
            return $c->redirect_to('/admin');
        } else {
            # Fork failed: return error to user
            return $c->alert('Failed to initiate restart command.', 500);
        }
    }

    # GET request: display restart confirmation form
    $c->render('admin/restart');
}


# Display system logs with filtering and pagination capabilities.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Redirect to login if not authenticated, alert on access denied, logs page render with filtered results.
sub logs ($c) {
    # Enforce user authentication for log access
    return $c->redirect_to('/login') unless $c->is_logged_in;
    # Enforce administrator privileges for system log viewing
    return $c->alert('Access denied. You must be an administrator to view this page.', 403) unless $c->is_admin;

    # Extract filtering parameters with sensible defaults
    my $limit = $c->param('limit') || 100;        # Number of log entries to display (default: 100)
    my $level = $c->param('level') || 'all';      # Log level filter (error, info, debug, all)
    my $category = $c->param('category') || 'all'; # Log category filter (system, user, security, all)

    # Retrieve filtered logs from database based on parameters
    my $logs = $c->db->get_recent_logs($limit, $level, $category);  # DB: fetch filtered log entries

    # Render logs page with data and current filter settings
    $c->render('admin/logs',
        logs     => $logs,     # Log entries for display
        limit    => $limit,    # Current limit setting for form
        level    => $level,    # Current level filter for form
        category => $category  # Current category filter for form
    );
}


1;

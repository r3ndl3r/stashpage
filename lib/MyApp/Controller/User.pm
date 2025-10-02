# /lib/MyApp/Controller/User.pm

package MyApp::Controller::User;

use Mojo::Base 'Mojolicious::Controller', -signatures;

use Mojo::Util qw(trim);

# Controller for user account management and self-service operations.

# Responsibilities:
# - Provides authenticated users access to account settings interface
# - Handles email address updates with validation and duplicate checking
# - Manages password changes with security verification
# - Enforces authentication and demo user restrictions
# - Implements comprehensive validation and error handling
# - Provides CSRF protection for all state-changing operations

# Security features:
# - Requires authentication for all account management operations
# - Validates CSRF tokens to prevent cross-site request forgery attacks
# - Verifies current password before allowing any account modifications
# - Blocks demo user from making account changes
# - Validates email format and checks for duplicate addresses
# - Enforces minimum password length requirements
# - Comprehensive audit logging for security monitoring

# Integration points:
# - Uses authentication helpers (is_logged_in, is_demo) for security
# - Integrates with DB helpers for user data operations
# - Utilizes session management for user context
# - Depends on logging system for security audit trail
# - Leverages Mojolicious validation system for CSRF protection

# Display account management page for authenticated users.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Rendered account settings template with current user information.
sub account ($c) {
    # Enforce user authentication for account access
    return $c->redirect_to('/login') unless $c->is_logged_in;
    
    my $username = $c->session('user');                    # Current authenticated username
    my $user_id = $c->db->get_user_id($username);          # DB: get user ID from username
    my $user_info = $c->db->get_user_by_id($user_id);     # DB: fetch user details by ID
    
    # Handle missing user data gracefully
    unless ($user_info && $user_info->{email}) {
        $c->app->log->error("User info not found for: $username (ID: $user_id)");
        return $c->alert('Unable to load account information', 500);
    }
    
    # Render account page with current user information
    $c->render(
        template => 'user/account',
        username => $username,
        email    => $user_info->{email}
    );
}

# Process email update request with comprehensive validation and security verification.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Redirect to account page with success/error flash message.
sub update_email ($c) {
    # Enforce user authentication for account modifications
    return $c->redirect_to('/login') unless $c->is_logged_in;
    
    # CSRF protection: validate token before processing request
    my $v = $c->validation;
    if ($v->csrf_protect->has_error('csrf_token')) {
        $c->app->log->warn("CSRF token validation failed for user: " . $c->session('user') . " from IP: " . $c->tx->remote_address);
        $c->flash(error => 'Security validation failed. Please try again.');
        return $c->redirect_to('/user/account');
    }
    
    # Block demo user from making account changes
    if ($c->is_demo) {
        $c->flash(error => 'Demo user cannot modify account settings');
        return $c->redirect_to('/user/account');
    }
    
    my $username         = $c->session('user');                    # Current authenticated username
    my $new_email        = trim($c->param('new_email') // '');     # New email with whitespace trimmed
    my $current_password = $c->param('current_password') // '';    # Password for verification
    
    # Validate required fields
    unless ($new_email && $current_password) {
        $c->flash(error => 'All fields are required');
        return $c->redirect_to('/user/account');
    }
    
    # Validate email format using comprehensive regex pattern
    unless ($new_email =~ /^[^\s@]+@[^\s@]+\.[^\s@]+$/) {
        $c->flash(error => 'Invalid email format');
        return $c->redirect_to('/user/account');
    }
    
    # Security: verify current password before allowing email change
    my $auth_result = $c->db->authenticate_user($username, $current_password);  # DB: verify credentials
    unless ($auth_result == 1) {
        $c->app->log->warn("Failed email update attempt - invalid password for user: $username from IP: " . $c->tx->remote_address);
        $c->log_event(
            level    => 'warning',
            category => 'auth',
            message  => "Failed email update - invalid password for user: $username"
        );
        $c->flash(error => 'Current password is incorrect');
        return $c->redirect_to('/user/account');
    }
    
    # Get user ID for database operations
    my $user_id = $c->db->get_user_id($username);                  # DB: get user ID
    my $user_info = $c->db->get_user_by_id($user_id);             # DB: get current user data
    
    # Check if email is already in use by another account
    if ($c->db->email_exists($new_email, $user_id)) {        # DB: check email availability
        $c->flash(error => 'Email address is already in use by another account');
        return $c->redirect_to('/user/account');
    }
    
    # Update email using existing update_user method
    eval {
        $c->db->update_user($user_id, $username, $new_email, $user_info->{is_admin});  # DB: update user record
    };
    
    if (my $error = $@) {
        # Database operation failed: log error and notify user
        $c->app->log->error("Failed to update email for user $username (ID: $user_id): $error");
        $c->log_event(
            level    => 'error',
            category => 'auth',
            message  => "Failed to update email for user: $username - $error"
        );
        $c->flash(error => 'Failed to update email. Please try again later.');
        return $c->redirect_to('/user/account');
    }
    
    # Log successful email update for audit trail
    $c->app->log->info("Email updated for user: $username (ID: $user_id) from IP: " . $c->tx->remote_address);
    $c->log_event(
        level    => 'info',
        category => 'auth',
        message  => "Email updated for user: $username to: $new_email"
    );
    
    $c->flash(message => 'Email address updated successfully');
    return $c->redirect_to('/user/account');
}

# Process password change request with comprehensive validation and security measures.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Redirect to account page with success/error flash message.
sub update_password ($c) {
    # Enforce user authentication for account modifications
    return $c->redirect_to('/login') unless $c->is_logged_in;
    
    # CSRF protection: validate token before processing request
    my $v = $c->validation;
    if ($v->csrf_protect->has_error('csrf_token')) {
        $c->app->log->warn("CSRF token validation failed for user: " . $c->session('user') . " from IP: " . $c->tx->remote_address);
        $c->flash(error => 'Security validation failed. Please try again.');
        return $c->redirect_to('/user/account');
    }
    
    # Block demo user from making account changes
    if ($c->is_demo) {
        $c->flash(error => 'Demo user cannot modify account settings');
        return $c->redirect_to('/user/account');
    }
    
    my $username         = $c->session('user');                      # Current authenticated username
    my $current_password = $c->param('current_password') // '';      # Current password for verification
    my $new_password     = $c->param('new_password') // '';          # New password from form
    my $confirm_password = $c->param('confirm_password') // '';      # Password confirmation
    
    # Comprehensive input validation
    unless ($current_password && $new_password && $confirm_password) {
        $c->flash(error => 'All password fields are required');
        return $c->redirect_to('/user/account');
    }
    
    # Enforce minimum password length requirement
    if (length($new_password) < 8) {
        $c->flash(error => 'New password must be at least 8 characters long');
        return $c->redirect_to('/user/account');
    }
    
    # Verify new passwords match
    unless ($new_password eq $confirm_password) {
        $c->flash(error => 'New passwords do not match');
        return $c->redirect_to('/user/account');
    }
    
    # Security: verify current password before allowing password change
    my $auth_result = $c->db->authenticate_user($username, $current_password);  # DB: verify credentials
    unless ($auth_result == 1) {
        $c->app->log->warn("Failed password change attempt - invalid current password for user: $username from IP: " . $c->tx->remote_address);
        $c->log_event(
            level    => 'warning',
            category => 'auth',
            message  => "Failed password change - invalid current password for user: $username"
        );
        $c->flash(error => 'Current password is incorrect');
        return $c->redirect_to('/user/account');
    }
    
    # Get user ID for password update
    my $user_id = $c->db->get_user_id($username);                  # DB: get user ID
    
    # Update password using existing method with secure hashing
    eval {
        $c->db->update_user_password($user_id, $new_password);     # DB: update password hash
    };
    
    if (my $error = $@) {
        # Database operation failed: log error and notify user
        $c->app->log->error("Failed to update password for user $username (ID: $user_id): $error");
        $c->log_event(
            level    => 'error',
            category => 'auth',
            message  => "Failed to update password for user: $username - $error"
        );
        $c->flash(error => 'Failed to update password. Please try again later.');
        return $c->redirect_to('/user/account');
    }
    
    # Log successful password change for audit trail
    $c->app->log->info("Password changed for user: $username (ID: $user_id) from IP: " . $c->tx->remote_address);
    $c->log_event(
        level    => 'info',
        category => 'auth',
        message  => "Password changed for user: $username"
    );
    
    $c->flash(message => 'Password changed successfully');
    return $c->redirect_to('/user/account');
}

1;

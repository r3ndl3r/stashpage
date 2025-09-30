# /lib/MyApp/Controller/Auth/Password.pm

package MyApp::Controller::Auth::Password;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::Util qw(trim);

# Controller for secure password recovery and reset operations.
# Responsibilities:
# - Provides forgot password interface with email validation
# - Implements rate limiting to prevent abuse of password reset system
# - Manages secure token-based password reset workflow
# - Handles password reset form validation and processing
# - Sends confirmation emails for password changes
# Security features:
# - Rate limiting on reset requests (max 3 per hour per email)
# - Secure token validation with expiration checking
# - Information disclosure protection (same response for valid/invalid emails)
# - Comprehensive audit logging for security monitoring
# Integration points:
# - Uses DB helpers for token management and user lookups
# - Integrates with email service for reset and confirmation notifications
# - Utilizes logging system for security audit trail

# Display forgot password form for user password recovery initiation.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Rendered forgot password form template.
sub forgot_form {
    my $c = shift;
    # Render forgot password form for password recovery request
    $c->render('auth/forgot_password');
}


# Process forgot password request with comprehensive security measures.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Alert on validation error or rate limit, redirect to login with success message.
sub forgot {
    my $c = shift;
    # Extract and sanitize email parameter from form
    my $email = trim($c->param('email') // '');     # Email address with whitespace trimmed
    
    # Validate email presence and format
    return $c->alert('Email address is required', 400) unless $email;
    return $c->alert('Invalid email format', 400)
        unless $email =~ /^[\w._%+-]+@[\w.-]+\.\w{2,}$/;
    
    # Security: rate limiting to prevent abuse of password reset system
    my $recent_requests = $c->db->count_recent_reset_requests($email, 60);  # DB: count requests in last 60 minutes
    if ($recent_requests >= 3) {
        # Rate limit exceeded: log security event and reject request
        $c->log_event(
            level => 'warning',
            category => 'auth',
            message => "Too many password reset requests for email: $email"
        );
        return $c->alert('Too many reset requests. Please wait before trying again.', 429);
    }
    
    # Check if user account exists for provided email
    my $user = $c->db->get_user_by_email($email);   # DB: lookup user by email address
    
    if ($user) {
        # User exists: create token and send reset email
        eval {
            # Create secure reset token with expiration
            my $token = $c->db->create_password_reset_token($user->{id});  # DB: generate reset token
            
            # Generate absolute URL for reset link in email
            my $reset_url = $c->url_for("/reset-password/$token")->to_abs;  # Full URL for email link
            # Integration: email service for password reset delivery
            $c->send_password_reset_email($user->{email}, $user->{username}, $reset_url);
            
            # Log successful reset email for audit trail
            $c->log_event(
                level => 'info',
                category => 'auth',
                message => "Password reset email sent to: $email"
            );
        };
        if ($@) {
            # Email sending failed: log error and notify user
            $c->app->log->error("Failed to send password reset email: $@");
            return $c->alert('Failed to send reset email. Please try again.', 500);
        }
    } else {
        # Security: log attempt for non-existent email but don't reveal existence
        $c->log_event(
            level => 'warning',
            category => 'auth',
            message => "Password reset requested for non-existent email: $email"
        );
    }
    
    # Security: always show success message to prevent email enumeration
    $c->flash(message => 'If an account with that email exists, you will receive a password reset link shortly.');
    return $c->redirect_to('/login');
}


# Display password reset form with secure token validation.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Alert on invalid token, rendered reset form on successful validation.
sub reset_form {
    my $c = shift;
    # Extract reset token from URL parameter
    my $token = $c->param('token');                 # Reset token from URL
    
    # Validate token presence
    return $c->alert('Invalid reset link', 400) unless $token;
    
    # Validate token authenticity and expiration
    my $user = $c->db->validate_reset_token($token);  # DB: check token validity and get user
    unless ($user) {
        # Invalid or expired token: log security event and reject
        $c->log_event(
            level => 'warning',
            category => 'auth',
            message => "Invalid or expired password reset token used: $token"
        );
        return $c->alert('This password reset link is invalid or has expired. Please request a new one.', 400);
    }
    
    # Valid token: prepare form with user context
    $c->stash(token => $token, username => $user->{username});  # Pass token and username to template
    $c->render('auth/reset_password');
}


# Process password reset with comprehensive validation and security measures.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Alert on validation error or failure, redirect to login on success.
sub reset {
    my $c = shift;
    # Extract form parameters for password reset
    my $token = $c->param('token');                     # Reset token from form
    my $password = $c->param('password');               # New password
    my $confirm_password = $c->param('confirm_password'); # Password confirmation
    
    # Comprehensive input validation
    return $c->alert('Invalid request', 400) unless $token;
    return $c->alert('Password is required', 400) unless $password;
    return $c->alert('Password confirmation is required', 400) unless $confirm_password;
    return $c->alert('Passwords do not match', 400) unless $password eq $confirm_password;
    return $c->alert('Password must be at least 8 characters', 400) if length($password) < 8;
    
    # Validate token authenticity and expiration again for security
    my $user = $c->db->validate_reset_token($token);    # DB: re-validate token before password change
    unless ($user) {
        # Token validation failed: log security event and reject
        $c->log_event(
            level => 'warning',
            category => 'auth',
            message => "Expired token used in password reset: $token"
        );
        return $c->alert('This password reset link is invalid or has expired. Please request a new one.', 400);
    }
    
    # Execute password reset with comprehensive error handling
    eval {
        # Update user password in database
        $c->db->reset_user_password($user->{user_id}, $password);  # DB: update password hash
        # Mark token as used to prevent replay attacks
        $c->db->use_reset_token($token);                          # DB: invalidate reset token
        
        # Log successful password reset for audit trail
        $c->log_event(
            level => 'info',
            category => 'auth',
            message => "Password successfully reset for user: $user->{username}"
        );
        
        # Send confirmation email with error handling
        eval {
            # Integration: email service for password change confirmation
            $c->send_password_change_notification($user->{email}, $user->{username});
        };
        if ($@) {
            # Log email failure but continue with password reset process
            $c->app->log->warn("Failed to send password change notification: $@");
        }
    };
    if ($@) {
        # Password reset failed: log error and notify user
        $c->app->log->error("Failed to reset password: $@");
        return $c->alert("Failed to reset password: $@", 500);
    }
    
    # Success: notify user and redirect to login
    $c->flash(message => 'Your password has been successfully reset. You can now log in with your new password.');
    return $c->redirect_to('/login');
}


1;

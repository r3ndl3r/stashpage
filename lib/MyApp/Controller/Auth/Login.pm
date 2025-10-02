# /lib/MyApp/Controller/Auth/Login.pm

package MyApp::Controller::Auth::Login;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::Util qw(trim);

# Controller for core authentication operations and user account management.
# Responsibilities:
# - Handles user login authentication with session management
# - Processes user logout with session cleanup and audit logging
# - Manages user registration with validation and approval workflow
# - Implements security features including failed login tracking
# - Initializes default stash data for new user accounts
# Integration points:
# - Uses DB helpers for user authentication and account management
# - Integrates with logging system for security audit trail
# - Depends on Pushover notifications for admin alerts
# - Utilizes session management for authentication state
# - Connects to stash initialization helpers for new users

# Display login form with optional message parameter for user feedback.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Rendered login form template with message parameter.
sub form {
    my $c = shift;
    # Render login form with optional message for user feedback
    $c->render('auth/login', msg => $c->param('msg'));  # Message for login status feedback
}


# Process user login authentication with comprehensive security logging.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Redirect to home on success, redirect to login with message on failure/pending.
sub login {
    my $c = shift;
    # Extract and sanitize login credentials from form
    my $username = trim($c->param('username') // '');  # Username with whitespace trimmed
    my $password = $c->param('password');              # Password (not trimmed to preserve spaces)
   
    # Authenticate user credentials against database
    my $auth_result = $c->db->authenticate_user($username, $password);  # DB: verify credentials
    if ($auth_result == 1) {
        # Successful authentication: establish session and log success
        $c->session(user => $username);                # Create authenticated session
        $c->app->log->info("User $username logged in from IP " . $c->tx->remote_address);
        $c->log_event(
            level => 'info',
            category => 'auth',
            message => "Successful login for user: $username"
        );
        return $c->redirect_to('/');                   # Redirect to dashboard
    } elsif ($auth_result == 2) {
        # User account pending approval: log attempt and redirect with message
        $c->app->log->warn("Pending approval login attempt for user $username from IP " . $c->tx->remote_address);
        $c->log_event(
            level => 'warning',
            category => 'auth',
            message => "Login attempt for pending user: $username"
        );
        return $c->redirect_to('/login?msg=pending');  # Show pending approval message
    } else {
        # Authentication failed: log attempt and check for brute force attacks
        $c->app->log->warn("Failed login attempt for user $username from IP " . $c->tx->remote_address);
        $c->log_event(
            level => 'warning',
            category => 'auth',
            message => "Failed login attempt for user: $username"
        );
       
        # Security: check for failed login patterns and potential brute force
        $c->check_failed_logins($username, $c->tx->remote_address);  # Security helper for attack detection
       
        return $c->redirect_to('/login?msg=invalid'); # Show invalid credentials message
    }
}


# Process user logout with session cleanup and audit logging.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Redirect to home page after session cleanup.
sub logout {
    my $c = shift;
    # Retrieve username before session destruction for logging
    my $username = $c->session('user');              # Current authenticated username
    $c->log_event(
        level => 'info',
        category => 'auth',
        message => "User logout: $username"
    );
    # Destroy user session by expiring it immediately
    $c->session(expires => 1);                       # Expire session to log out user
    return $c->redirect_to('/');                     # Redirect to home page
}


# Display user registration form for new account creation.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Rendered registration form template.
sub register_form {
    my $c = shift;
    # Render registration form for new user account creation
    $c->render('auth/register');
}


# Process user registration with comprehensive validation and initialization.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Alert on validation error or success, redirect prevented by alert response.
sub register {
    my $c = shift;
    # Extract and sanitize registration form parameters
    my $username = trim($c->param('username') // ''); # Username with whitespace trimmed
    my $password = $c->param('password');             # Password (preserve all characters)
    my $email    = trim($c->param('email') // '');    # Email address with whitespace trimmed
   
    # Comprehensive input validation with security constraints
    return $c->alert('Invalid username', 400) unless $username =~ /^[\w._]{3,20}$/;
    return $c->alert('Password too short', 400) if length($password) < 8;
    return $c->alert('Invalid email', 400)
      unless $email =~ /^[\w._%+-]+@[\w.-]+\.\w{2,}$/;
   
    # Check for existing username to prevent duplicates
    if ($c->db->user_exists($username)) {             # DB: check username availability
        $c->log_event(
            level => 'warning',
            category => 'auth',
            message => "Registration attempt with existing username: $username"
        );
        return $c->alert('Username already exists', 400);
    }

    # Check for existing email address to prevent duplicates
    if ($c->db->email_exists($email)) {               # DB: check email availability
        $c->log_event(
            level => 'warning',
            category => 'auth',
            message => "Registration attempt with existing email: $email"
        );
        return $c->alert('Email address already in use. Use reset password!', 400);
    }

    # Create user account with error handling for database failures
    eval { $c->db->create_user($username, $password, $email); };  # DB: insert new user record
    if (my $error = $@) {
        # Database operation failed: log error and notify user
        $c->app->log->error("Failed to create user: $error");
        $c->log_event(
            level => 'error',
            category => 'auth',
            message => "Failed to create user $username: $error"
        );
        return $c->alert("Error creating user: $error", 500);
    }
   
    # Initialize default stash data for new user with error handling
    eval {
        my $user_id = $c->db->get_user_id($username);   # DB: retrieve new user ID
        if ($user_id) {
            # Integration: stash initialization helper for user onboarding
            $c->initialize_default_stash_for_user($user_id);
            $c->app->log->info("Default stash initialized for new user: $username");
        } else {
            $c->app->log->warn("Could not get user ID for $username to initialize default stash");
        }
    };
    if (my $error = $@) {
        # Log stash initialization failure but continue with registration
        $c->app->log->warn("Failed to initialize default stash for user $username: $error");
    }
   
    # Log successful registration for audit trail
    $c->app->log->info("New user registered: $username from IP " . $c->tx->remote_address);
    
    # Send admin notification via Pushover with error handling
    eval {
        # Integration: Pushover helper for real-time admin notifications
        $c->send_pushover(
            "New user registration pending approval:\nUsername: $username\nEmail: $email",
            "New User Registration"
        );
    };
    if ($@) {
        # Log notification failure but continue with registration process
        $c->log_event(
            level => 'warning',
            category => 'admin',
            message => "Failed to send Pushover notification for new user $username: $@"
        );
    }
    
    # Log registration event for comprehensive audit trail
    $c->log_event(
        level => 'info',
        category => 'auth',
        message => "New user registered: $username (email: $email)"
    );
    
    # Check if user was auto-approved (first user)
    my $user_info = $c->db->get_user_by_username($username);
    if ($user_info && $user_info->{status} eq 'approved') {
        return $c->alert("Registration successful!<br>You can now log in with your credentials.", 200);
    } else {
        return $c->alert("Registration successful!<br>Please wait for administrator approval before attempting to log in.", 200);
    }

}
1;

1;

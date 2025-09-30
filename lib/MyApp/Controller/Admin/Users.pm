# /lib/MyApp/Controller/Admin/Users.pm

package MyApp::Controller::Admin::Users;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::Util qw(trim);

# Controller for administrative user management operations.
# Responsibilities:
# - Displays paginated list of all users with status information
# - Handles user deletion with validation and cascading cleanup
# - Manages user approval workflow with email notifications
# - Provides user editing interface with comprehensive validation
# - Enforces administrative access control on all user operations
# Integration points:
# - Uses authentication helpers (is_logged_in, is_admin) for security
# - Integrates with DB helpers for user CRUD operations
# - Depends on email service for approval notifications
# - Utilizes logging system for audit trail and error tracking

# Display paginated list of all users with status and role information.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Redirect to login if not authenticated, alert on access denied, users list render on success.
sub list {
    my $c = shift;
    # Enforce user authentication for admin user list access
    return $c->redirect_to('/login') unless $c->is_logged_in;
    # Enforce administrator privileges for user management
    return $c->alert('Access denied.', 403) unless $c->is_admin;
    
    # Retrieve all users from database for administrative overview
    my $users = $c->db->get_all_users();  # DB: fetch complete user list with status
    $c->stash(users => $users);           # Pass user data to template
    $c->render('admin/users');            # Render admin users list page
}


# Delete user by ID with validation and cascading cleanup.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Alert on access denied or validation error, redirect to users list on success.
sub delete {
    my $c = shift;
    # Enforce administrator privileges for user deletion
    return $c->alert('Access denied. You must be an administrator to view this page.', 403) unless $c->is_admin;
    
    # Extract and validate user ID parameter
    my $id = $c->param('id');                    # User ID from URL parameter
    unless (defined $id && $id =~ /^\d+$/) {
        return $c->alert('Invalid user ID', 400);
    }
    
    # Execute user deletion with cascading cleanup of associated data
    $c->db->delete_user($id);                    # DB: remove user and related records
    return $c->redirect_to('/users');           # Redirect to prevent resubmission
}


# Approve pending user registration with email notification.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Alert on access denied or validation error, redirect to users list on success.
sub approve {
    my $c = shift;
    # Enforce administrator privileges for user approval
    return $c->alert('Access denied. You must be an administrator to view this page.', 403) unless $c->is_admin;
    
    # Extract and validate user ID parameter
    my $id = $c->param('id');                    # User ID from URL parameter
    unless (defined $id && $id =~ /^\d+$/) {
        return $c->alert('Invalid user ID', 400);
    }
    
    # Retrieve user details for notification email before approval
    my $user_details = $c->db->get_user_details($id);  # DB: fetch user info for email
    $c->db->approve_user($id);                          # DB: update user status to approved
    
    # Send approval notification email if user has valid email address
    if ($user_details && $user_details->{email}) {
        eval {
            # Integration: email service for user notification
            $c->send_approval_notification($user_details->{username}, $user_details->{email});
            $c->app->log->info("Approval email sent to " . $user_details->{email});
        };
        if ($@) {
            # Log email failure but continue with approval process
            $c->app->log->warn("Failed to send approval email: $@");
        }
    }
    
    return $c->redirect_to('/users');           # Redirect to prevent resubmission
}


# Display user edit form with current user data populated.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Alert on access denied, validation error, or user not found, edit form render on success.
sub edit_form {
    my $c = shift;
    # Enforce administrator privileges for user editing
    return $c->alert('Access denied. You must be an administrator to view this page.', 403) unless $c->is_admin;
    
    # Extract and validate user ID parameter
    my $id = $c->param('id');                    # User ID from URL parameter
    unless (defined $id && $id =~ /^\d+$/) {
        return $c->alert('Invalid user ID', 400);
    }
    
    # Retrieve user data for form population
    my $user = $c->db->get_user_by_id($id);     # DB: fetch user record for editing
    unless ($user) {
        return $c->alert('User not found', 404);
    }
    
    # Pass user data to edit template
    $c->stash(user => $user);                   # User data for form population
    $c->render('admin/users_edit');             # Render user edit form
}


# Process user edit form submission with validation and database update.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Alert on access denied or validation error, redirect to users list on success.
sub edit {
    my $c = shift;
    # Enforce administrator privileges for user modification
    return $c->alert('Access denied. You must be an administrator to view this page.', 403) unless $c->is_admin;
    
    # Extract and sanitize form parameters
    my $id = $c->param('id');                           # User ID from form
    my $username = trim($c->param('username') // '');  # Username with whitespace trimmed
    my $email = trim($c->param('email') // '');        # Email address with whitespace trimmed
    my $is_admin = $c->param('is_admin') ? 1 : 0;      # Admin status checkbox (boolean conversion)
    my $password = $c->param('password');              # Optional new password
    
    # Validate user ID format
    unless (defined $id && $id =~ /^\d+$/) {
        return $c->alert('Invalid user ID', 400);
    }
    
    # Validate username format and length constraints
    return $c->alert('Invalid username', 400) unless $username =~ /^[\w._]{3,20}$/;
    # Validate email format using comprehensive regex pattern
    return $c->alert('Invalid email', 400)
        unless $email =~ /^[\w._%+-]+@[\w.-]+\.\w{2,}$/;
    
    # Handle optional password update with validation
    if (defined $password && length $password > 0) {
        # Enforce minimum password length for security
        return $c->alert('Password too short', 400) if length($password) < 8;
        $c->db->update_user_password($id, $password);   # DB: update password separately
    }
    
    # Update user profile information in database
    $c->db->update_user($id, $username, $email, $is_admin);  # DB: update user record
    return $c->redirect_to('/users');                        # Redirect to prevent resubmission
}


1;

# /lib/MyApp/Controller/Admin/Settings.pm

package MyApp::Controller::Admin::Settings;

use Mojo::Base 'Mojolicious::Controller', -signatures;
use Mojo::Util qw(trim);

# Controller for administrative settings configuration management.
# Responsibilities:
# - Handles Pushover notification service configuration with credential validation
# - Manages Gmail SMTP email configuration with app password authentication  
# - Provides email testing functionality with comprehensive error handling
# - Enforces administrative access control on all settings endpoints
# Integration points:
# - Uses authentication helpers (is_logged_in, is_admin) for security
# - Integrates with DB helpers for settings persistence
# - Depends on email service integration for test functionality

# Configure Pushover notification service settings.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Redirect to login if not authenticated, alert on access denied, form render or redirect on success.
sub pushover ($c) {
    # Enforce user authentication for settings access
    return $c->redirect_to('/login') unless $c->is_logged_in;
    # Enforce administrator privileges for settings modification
    return $c->alert('Access denied. You must be an administrator to view this page.', 403) unless $c->is_admin;
    
    if ($c->req->method eq 'POST') {
        # Extract and sanitize form parameters
        my $user_key = trim($c->param('user_key') // '');    # Pushover user key for notifications
        my $app_token = trim($c->param('app_token') // '');  # Pushover application token
        
        # Validate required Pushover API credentials
        return $c->alert('User key is required', 400) unless $user_key;
        return $c->alert('App token is required', 400) unless $app_token;
        
        # Save configuration to database with error handling
        eval {
            $c->db->save_pushover_settings($user_key, $app_token);
        };
        if ($@) {
            # Database operation failed, return error to user
            return $c->alert("Failed to save settings: $@", 500);
        }
        
        # Success: notify user and redirect to prevent form resubmission
        $c->flash(message => 'Pushover settings saved successfully');
        return $c->redirect_to('/admin/pushover');
    }
    
    # GET request: load current Pushover settings for form display
    my $settings = $c->db->get_pushover_settings();
    $c->render('admin/pushover', settings => $settings);
}


# Configure Gmail SMTP email service settings.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Redirect to login if not authenticated, alert on access denied, form render or redirect on success.
sub email ($c) {
    # Enforce user authentication for settings access
    return $c->redirect_to('/login') unless $c->is_logged_in;
    # Enforce administrator privileges for email configuration
    return $c->alert('Access denied. You must be an administrator to view this page.', 403) unless $c->is_admin;
    
    if ($c->req->method eq 'POST') {
        # Extract and sanitize email configuration parameters
        my $gmail_email = trim($c->param('gmail_email') // '');               # Gmail address for SMTP authentication
        my $gmail_app_password = trim($c->param('gmail_app_password') // ''); # Gmail app-specific password
        my $from_name = trim($c->param('from_name') // 'Stashpage');         # Display name for outgoing emails
        
        # Validate Gmail SMTP configuration requirements
        return $c->alert('Gmail email is required', 400) unless $gmail_email;
        return $c->alert('Gmail app password is required', 400) unless $gmail_app_password;
        # Enforce Gmail domain restriction for SMTP compatibility
        return $c->alert('Invalid email format', 400) 
            unless $gmail_email =~ /^[\w._%+-]+\@gmail\.com$/;
        
        # Save email configuration to database with transaction safety
        eval {
            $c->db->save_email_settings($gmail_email, $gmail_app_password, $from_name);
        };
        if ($@) {
            # Database operation failed, return error to user
            return $c->alert("Failed to save settings: $@", 500);
        }
        
        # Success: notify user and redirect to prevent form resubmission
        $c->flash(message => 'Email settings saved successfully');
        return $c->redirect_to('/admin/email');
    }
    
    # GET request: load current email configuration for form display
    my $settings = $c->db->get_email_settings();
    $c->render('admin/email', settings => $settings);
}


# Test email functionality using current SMTP configuration.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   JSON response with success/error status and message.
sub email_test ($c) {
    # Enforce authentication and admin privileges for email testing
    return $c->render(json => { error => 'Unauthorized' }, status => 401) 
        unless $c->is_logged_in && $c->is_admin;
    
    # Extract JSON payload from request body
    my $data = $c->req->json;
    my $test_email = $data->{test_email};  # Target email address for test message
    
    # Validate test email address format and presence
    return $c->render(json => { error => 'Test email address required' }, status => 400) 
        unless $test_email;
    
    # Validate email format using comprehensive regex pattern
    return $c->render(json => { error => 'Invalid email format' }, status => 400)
        unless $test_email =~ /^[\w._%+-]+@[\w.-]+\.\w{2,}$/;
    
    # Attempt email delivery with detailed logging for troubleshooting
    $c->app->log->info("Attempting to send test email to: $test_email");
    my $result = $c->send_test_email($test_email);  # Integration: email service helper
    $c->app->log->info("Test email result: " . ($result ? "SUCCESS" : "FAILED"));
    
    # Return JSON response based on email delivery result
    if ($result) {
        $c->render(json => { success => 1, message => 'Test email sent successfully' });
    } else {
        $c->render(json => { error => 'Failed to send test email' }, status => 500);
    }
}


1;

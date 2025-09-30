# /lib/MyApp/Plugin/Email.pm

package MyApp::Plugin::Email;

use Mojo::Base 'Mojolicious::Plugin', -signatures;
use strict;
use warnings;

# Email delivery system plugin for stash management application.
# Responsibilities:
# - Provides Gmail SMTP integration with TLS encryption and authentication
# - Handles template-based email notifications for user account management
# - Implements password reset and approval notification workflows
# - Offers email testing functionality for administrative verification
# - Manages secure credential storage and dynamic configuration loading
# Integration points:
# - Uses DB helpers for email settings and credential management
# - Integrates with logging system for delivery tracking and error reporting
# - Connects to authentication system for security event notifications

# Register email delivery helpers with the application.
# Parameters:
#   $self   : Instance of plugin.
#   $app    : Mojolicious app object.
#   $config : Hashref of configuration overrides (optional).
# Returns:
#   None. Registers email helpers in $app.
sub register ($self, $app, $config = {}) {
    # Configuration defaults for SMTP connection and behavior settings
    my $smtp_timeout = $config->{smtp_timeout} || 30;     # SMTP connection timeout in seconds
    my $smtp_host = $config->{smtp_host} || 'smtp.gmail.com';  # Gmail SMTP server
    my $smtp_port = $config->{smtp_port} || 587;          # STARTTLS port for Gmail
    my $debug_email = $config->{debug_email} || 0;        # SMTP debug output flag

    # Helper: send_email_via_gmail
    # Core Gmail SMTP email delivery with TLS encryption.
    # Parameters:
    #   $c      : Mojolicious controller (calling context).
    #   $to     : Recipient email address.
    #   $subject: Email subject line.
    #   $body   : Email message body.
    # Returns:
    #   Boolean: 1 on successful delivery, 0 on failure.
    $app->helper(send_email_via_gmail => sub ($c, $to, $subject, $body) {
        # Load email configuration from database for dynamic settings
        my $email_settings = $c->db->get_email_settings();  # DB: get SMTP credentials
        
        # Validate required email configuration before connection attempt
        unless ($email_settings->{gmail_email} && $email_settings->{gmail_app_password}) {
            $c->app->log->error("Email settings not configured properly - missing credentials");
            return 0;
        }
        
        # Dynamic module loading for optional email feature
        require Net::SMTP;
        
        my $success = 0;
        
        # Comprehensive SMTP operation with error handling
        eval {
            # Establish secure SMTP connection with timeout protection
            my $smtp = Net::SMTP->new($smtp_host,
                Port => $smtp_port,
                Timeout => $smtp_timeout,
                Debug => $debug_email
            ) or die "Cannot connect to SMTP server $smtp_host:$smtp_port: $!";
            
            # Initiate TLS encryption for credential protection
            $smtp->starttls() or die "STARTTLS negotiation failed";
            
            # Authenticate using Gmail app password
            $smtp->auth($email_settings->{gmail_email}, $email_settings->{gmail_app_password}) 
                or die "SMTP authentication failed: " . $smtp->message;
            
            # Set envelope sender and recipient
            $smtp->mail($email_settings->{gmail_email}) or die "MAIL FROM command failed";
            $smtp->to($to) or die "RCPT TO command failed for recipient: $to";
            
            # Begin message transmission
            $smtp->data() or die "DATA command failed";
            
            # Construct sender header with optional display name
            my $from_header = $email_settings->{from_name} 
                ? "$email_settings->{from_name} <$email_settings->{gmail_email}>"
                : $email_settings->{gmail_email};
                
            # Send RFC-compliant email headers
            $smtp->datasend("From: $from_header\n");
            $smtp->datasend("To: $to\n");
            $smtp->datasend("Subject: $subject\n");
            $smtp->datasend("Content-Type: text/plain; charset=UTF-8\n");
            $smtp->datasend("\n");                          # Headers/body separator
            
            # Transmit message body and complete transmission
            $smtp->datasend("$body\n");
            $smtp->dataend() or die "Failed to complete message data transmission";
            
            # Close SMTP connection properly
            $smtp->quit();
            
            $success = 1;                                   # Mark successful delivery
            $c->app->log->info("Email sent successfully to: $to (Subject: $subject)");
        };
        
        # Log detailed error information for debugging
        if (my $error = $@) {
            $c->app->log->error("Failed to send email to $to: $error");
            $c->log_event(
                level => 'error',
                category => 'email',
                message => "Email delivery failure to $to: $error"
            );
            return 0;
        }
        
        return $success;
    });

    # Helper: send_approval_notification
    # Sends account approval notification to newly approved users.
    # Parameters:
    #   $c        : Mojolicious controller (calling context).
    #   $username : Username of approved user.
    #   $email    : Email address for notification.
    # Returns:
    #   Boolean: email delivery result.
    $app->helper(send_approval_notification => sub ($c, $username, $email) {
        my $subject = "Your Stashpage Account Has Been Approved";    # Approval subject line
        my $dashboard_url = $c->url_for('/')->to_abs;                # Full dashboard URL
        
        # Template-based approval email with access instructions
        my $body = qq{Hello $username,

Great news! Your Stashpage account has been approved and you can now log in.

You can access your dashboard at: $dashboard_url

Welcome to Stashpage! Your personal bookmark dashboard is now ready for use.

Best regards.};
        
        # Use core email delivery system
        return $c->send_email_via_gmail($email, $subject, $body);
    });

    # Helper: send_test_email
    # Administrative email testing functionality.
    # Parameters:
    #   $c         : Mojolicious controller (calling context).
    #   $test_email: Email address for test message.
    # Returns:
    #   Boolean: email delivery result.
    $app->helper(send_test_email => sub ($c, $test_email) {
        my $subject = "Stashpage Email Configuration Test";          # Test email subject
        my $timestamp = scalar(localtime());                        # Current timestamp
        my $sender_ip = $c->tx->remote_address || 'Unknown IP';     # Request IP address
        
        # Diagnostic email template with system information
        my $body = qq{This is a test email from your Stashpage installation.

If you are receiving this email, your email configuration is working correctly!

System Information:
- Timestamp: $timestamp  
- Sender IP: $sender_ip
- Test initiated by: } . ($c->session('user') || 'Unknown user') . qq{

Stashpage Email System
Configuration Test Successful};
        
        # Attempt delivery with enhanced logging for test results
        my $result = $c->send_email_via_gmail($test_email, $subject, $body);
        $c->app->log->info("Test email delivery result: " . (defined $result ? ($result ? "SUCCESS" : "FAILED") : "ERROR"));
        
        return $result;
    });

    # Helper: send_password_reset_email
    # Secure password reset email delivery with token.
    # Parameters:
    #   $c         : Mojolicious controller (calling context).
    #   $email     : User's email address.
    #   $username  : Username for personalization.
    #   $reset_url : Secure reset URL with token.
    # Returns:
    #   Boolean: email delivery result.
    $app->helper(send_password_reset_email => sub ($c, $email, $username, $reset_url) {
        my $subject = "Reset Your Stashpage Password";              # Password reset subject
        
        # Security-focused email template with reset instructions
        my $body = qq{Hello $username,

You recently requested to reset your password for your Stashpage account.

To reset your password, click the link below:
$reset_url

IMPORTANT SECURITY INFORMATION:
- This link will expire in 30 minutes for your security
- If you did not request this password reset, please ignore this email
- Your current password will remain unchanged until you complete the reset process
- Only use this link if you initiated the password reset request

For security questions or concerns, please contact your administrator.

Best regards.};
        
        # Deliver reset email with security event logging
        my $result = $c->send_email_via_gmail($email, $subject, $body);
        $c->log_event(
            level => 'info',
            category => 'security',
            message => "Password reset email sent to: $email for user: $username"
        );
        
        return $result;
    });

    # Helper: send_password_change_notification
    # Password change confirmation and security alert.
    # Parameters:
    #   $c        : Mojolicious controller (calling context).
    #   $email    : User's email address.
    #   $username : Username for personalization.
    # Returns:
    #   Boolean: email delivery result.
    $app->helper(send_password_change_notification => sub ($c, $email, $username) {
        my $subject = "Stashpage Password Successfully Changed";    # Change confirmation subject
        my $timestamp = scalar(localtime());                       # Change timestamp
        
        # Security notification template with unauthorized access guidance
        my $body = qq{Hello $username,

Your Stashpage password has been successfully changed.

If you made this change, no further action is required.

SECURITY ALERT: If you did not change your password, please take immediate action:
1. Contact your administrator immediately
2. Your account may have been compromised
3. Do not ignore this notification

Change Details:
- Timestamp: $timestamp
- Account: $username
- Action: Password successfully updated

Best regards.};
        
        # Send security notification with audit logging
        my $result = $c->send_email_via_gmail($email, $subject, $body);
        $c->log_event(
            level => 'info', 
            category => 'security',
            message => "Password change notification sent to: $email for user: $username"
        );
        
        return $result;
    });
}


1;

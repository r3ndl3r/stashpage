# /lib/MyApp/Plugin/Core.pm

package MyApp::Plugin::Core;

use Mojo::Base 'Mojolicious::Plugin', -signatures;
use strict;
use warnings;

# Core plugin for stash management application.
# Responsibilities:
#   - Registers helpers for event logging, push notification integration, and standardized alert rendering.
#   - Integrates with app configuration, DB models, hook system.
#   - Centralizes business logic for audits, compliance, monitoring, and user feedback.


sub register ($self, $app, $config = {}) {
    # Registers core helpers with the Mojolicious application.
    # Parameters:
    #   $self   : Instance of plugin.
    #   $app    : Mojolicious app object.
    #   $config : Hashref of configuration overrides (optional).
    # Returns:
    #   None. Registers helpers in $app.

    my $pushover_timeout      = $config->{pushover_timeout}      || 30;   # Max seconds for Pushover API requests
    my $default_alert_status  = $config->{default_alert_status}  || 400;  # Default HTTP status for alerts
    my $log_user_agents       = $config->{log_user_agents}       // 1;    # Flag: log user agent info if true

    # Helper: log_event
    # Logs a security, application, or user event with detailed context.
    # Parameters:
    #   $c      : Mojolicious controller (calling context).
    #   %params : Event attributes, may be partial (helper auto-fills known context).
    # Returns:
    #   DB response/enqueued event log record (caller may check for errors).
    $app->helper(log_event => sub ($c, %params) {
        # Fill user identification context if possible.
        $params{user_id}   ||= $c->can('current_user_id') && $c->is_logged_in ? $c->current_user_id : undef;
        $params{username}  ||= $c->session('user') ? $c->session('user') : undef;
        # Network and session info for audit/forensics.
        $params{ip_address}    ||= $c->tx->remote_address;
        $params{request_path}  ||= $c->req->url->path->to_string;
        $params{session_id}    ||= $c->session('id');
        # Optional device/browser context.
        $params{user_agent}    ||= $log_user_agents ? $c->req->headers->user_agent : undef;

        # Integration: passes event to DB subsystem for persistent storage.
        return $c->db->log_event(%params);
    });

    # Helper: send_pushover
    # Sends a notification via Pushover API (external real-time alert service).
    # Parameters:
    #   $c      : Mojolicious controller (usage context).
    #   $message: String message to deliver.
    #   $title  : Optional string (notification title). Default 'Stashpage Alert'.
    # Returns:
    #   Boolean: success status (true if delivered, false on failure/config error).
    $app->helper(send_pushover => sub ($c, $message, $title = 'Stashpage Alert') {
        my $settings = $c->db->get_pushover_settings(); # DB: fetch latest credentials/settings
        return 0 unless $settings->{user_key} && $settings->{app_token};
        require LWP::UserAgent;
        my $ua = LWP::UserAgent->new(timeout => $pushover_timeout);

        my $response = $ua->post('https://api.pushover.net/1/messages.json', {
            token   => $settings->{app_token},   # Pushover app token
            user    => $settings->{user_key},    # Recipient key/group
            message => $message,                 # Message body
            title   => $title                    # Notification title
        });

        return $response->is_success;
    });

    # Helper: alert
    # Renders a standardized user-facing alert/error message.
    # Parameters:
    #   $c      : Mojolicious controller (context).
    #   $msg    : String alert message for user.
    #   $status : Optional HTTP status code (default value if omitted).
    # Returns:
    #   None (response rendered).
    $app->helper(alert => sub ($c, $msg, $status = undef) {
        my $response_status = $status // $default_alert_status;
        # Passes alert message and login status to stash for template integration.
        $c->stash(
            message      => $msg,
            is_logged_in => $c->is_logged_in
        );
        # Renders 'alert' template with correct status code and context.
        $c->render('alert', status => $response_status);
    });

    # Hook: after_dispatch
    # Post-response hook (fires after request completes).
    # Logs all server errors (status >= 500) via event log helper.
    $app->hook(after_dispatch => sub ($c) {
        my $status = $c->res->code;
        if ($status && $status >= 500) {
            $c->log_event(
                level        => 'error',
                category     => 'system',
                message      => "HTTP $status error on " . $c->req->url->path->to_string,
                status_code  => $status
            );
        }
    });
}

1;

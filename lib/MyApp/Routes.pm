# /lib/MyApp/Routes.pm

package MyApp::Routes;
use strict;
use warnings;

# Central route registration module for Stashpage application.
# Responsibilities:
# - Defines all HTTP routes and maps them to controller actions
# - Organizes routes by functional area (authentication, admin, stash management)
# - Provides RESTful API endpoints for AJAX operations and data exchange
# - Maintains backward compatibility with legacy route structures
# - Establishes URL patterns for user navigation and external integration
# Integration points:
# - Maps routes to controller namespaces and action methods
# - Supports both GET/POST patterns and RESTful API design
# - Integrates with authentication middleware for access control

# Configure application routing table with controller mappings.
# Parameters:
#   $app : Mojolicious application instance.
# Returns:
#   None. Configures routes in application router.
sub setup_routes {
    my $app = shift;
    my $r = $app->routes;                                    # Application router instance

    # =============================================================================
    # AUTHENTICATION AND USER MANAGEMENT ROUTES
    # =============================================================================
    
    # User authentication workflow routes
    $r->get('/login')->to('auth-login#form');               # Display login form
    $r->post('/login')->to('auth-login#login');             # Process login credentials
    $r->get('/logout')->to('auth-login#logout');            # Process user logout
    $r->get('/register')->to('auth-login#register_form');   # Display registration form
    $r->post('/register')->to('auth-login#register');       # Process user registration

    # Password recovery workflow routes
    $r->get('/forgot-password')->to('auth-password#forgot_form');      # Display forgot password form
    $r->post('/forgot-password')->to('auth-password#forgot');          # Process password reset request
    $r->get('/reset-password/:token')->to('auth-password#reset_form'); # Display reset form with token
    $r->post('/reset-password')->to('auth-password#reset');            # Process password reset with new password

    # =============================================================================
    # ADMINISTRATIVE INTERFACE ROUTES
    # =============================================================================
    
    # System administration and monitoring routes
    $r->get('/admin')->to('admin-system#index');                       # Admin dashboard overview
    $r->get('/admin/logs')->to('admin-system#logs');                   # System logs with filtering
    $r->any('/admin/restart')->to('admin-system#restart');             # Application restart interface
    $r->get('/admin/maintenance')->to('admin-system#maintenance');     # Maintenance mode display
    $r->post('/admin/maintenance')->to('admin-system#maintenance');    # Maintenance mode toggle

    # User management administrative routes
    $r->get('/users')->to('admin-users#list');                         # User listing (primary route)
    $r->get('/admin/users')->to('admin-users#list');                   # User listing (alternate route)
    $r->get('/user/:id/delete')->to('admin-users#delete');             # Delete user account
    $r->get('/user/:id/approve')->to('admin-users#approve');           # Approve pending user
    $r->get('/user/:id/edit')->to('admin-users#edit_form');            # Display user edit form
    $r->post('/user/:id/edit')->to('admin-users#edit');                # Process user edit submission

    # System settings and configuration routes
    $r->get('/admin/settings')->to('admin-settings#index');            # Settings overview page
    $r->any('/admin/pushover')->to('admin-settings#pushover');         # Pushover notification config
    $r->any('/admin/email')->to('admin-settings#email');               # Email SMTP configuration
    $r->post('/admin/email/test')->to('admin-settings#email_test');    # Email delivery testing

    # =============================================================================
    # STASH DASHBOARD AND DISPLAY ROUTES
    # =============================================================================
    
    # Primary dashboard and viewing routes
    $r->get('/')->to('stash-display#index');                           # Home dashboard (root route)
    $r->get('/stash')->to('stash-display#index');                      # Stash dashboard (explicit route)
    $r->get('/edit')->to('stash-display#edit');                        # Edit interface for stash pages

    # =============================================================================
    # STASH PAGE MANAGEMENT ROUTES
    # =============================================================================
    
    # Page lifecycle management routes
    $r->post('/stash/delete')->to('stash-pages#delete');               # Delete stash page permanently
    $r->post('/stash/rename')->to('stash-pages#rename');               # Rename existing stash page
    $r->post('/stash/clone')->to('stash-pages#clone');                 # Clone stash page with new name
    $r->get('/api/v1/stash/pages')->to('stash-pages#list');            # API: list user's stash pages
    $r->get('/api/search')->to('stash-data#search');                   # API: search bookmarks across all stashes


    # =============================================================================
    # STASH DATA MANAGEMENT ROUTES
    # =============================================================================
    
    # Data persistence and manipulation routes
    $r->post('/edit')->to('stash-data#save');                                          # Save stash page edits to database
    $r->post('/api/v1/stash/category/toggle')->to('stash-data#toggle_category_state'); # AJAX: toggle category collapse
    $r->post('/api/v1/stash/toggle-public')->to('stash-data#toggle_public');           # API: toggle public/private visibility
    $r->get('/stash/export')->to('stash-data#export');                                 # Export stash data as JSON
    $r->post('/stash/import')->to('stash-data#import');                                # Import stash data from JSON
    

    # ============================================================================
    # User Account Management Routes
    # ============================================================================

    $r->get('/user/account')->to('user#account');
    $r->post('/user/update-email')->to('user#update_email');
    $r->post('/user/update-password')->to('user#update_password');
}

1;

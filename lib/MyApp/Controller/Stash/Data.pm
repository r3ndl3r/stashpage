# /lib/MyApp/Controller/Stash/Data.pm

package MyApp::Controller::Stash::Data;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw(decode_json encode_json);
use JSON ();

# Controller for handling stash data operations.
# Features:
#   - Save stash page edits
#   - Toggle category collapsed/expanded state
#   - Import/export stash data for user backup/restore
# Integration points:
#   - Depends on authentication context
#   - Uses DB helpers for persistent storage

# Saves stash page data from edit interface.
# Route: POST /stash/data/save
# Parameters:
#   page_key    : Identifier for the stash page (must match /^[\w_\-.]+$/)
#   stash_data  : JSON payload with edited categories.
# Returns:
#   Redirects on success (to stash page), or error alert on failure/validation error
sub save {
    my $c = shift;
    return $c->redirect_to('/login') unless $c->is_logged_in;

    my $page_key = $c->param('page_key');
    my $json_text = $c->param('stash_data');
    
    # Validate page name format
    return $c->alert('Invalid page name.', 400) 
        unless $page_key && $page_key =~ /^[\w_\-.]+$/;

    # Parse JSON data from edit interface
    my $categories = eval { decode_json($json_text) };
    return $c->alert('Invalid JSON.', 400) if $@;
    
    # Save page data and redirect to view mode
    if ($c->save_stash_page_data($page_key, $categories)) {
        return $c->redirect_to("/stash?n=$page_key");
    } else {
        return $c->alert("Failed to save: " . ($c->db->{dbh}->errstr || ($c->is_demo ? 'demo account cannot save edits' : 'Unknown error')), 500);

    }
}

# Toggles collapsed/expanded state of a category via AJAX.
# Route: POST /stash/data/toggle_category_state
# Parameters (JSON):
#   page_key       : Page key for stash collection (must match /^[\w_\-.]+$/)
#   category_title : Category to modify
#   state          : New collapsed (0) or expanded (1) state
# Returns:
#   JSON response: { success: 1 } on success
#   JSON error: { error: '...' } with status code on failure
sub toggle_category_state { 
    my $c = shift;
    
    # Verify user authentication
    return $c->render(json => { error => 'Unauthorized' }, status => 401)
        unless $c->is_logged_in;

    # Get JSON request body
    my $data = $c->req->json;
    my $page_key = $data->{page_key};
    my $category_title = $data->{category_title};
    my $state = $data->{state};

    # Validate required parameters (state can be 0, so use 'defined')
    unless (defined $page_key && defined $category_title && defined $state) {
        return $c->render(json => { error => 'Missing required parameters' }, status => 400);
    }
    
    # Validate page key format for security
    return $c->render(json => { error => 'Invalid page name' }, status => 400)
        unless $page_key =~ /^[\w_\-.]+$/;

    # Save category state and respond with JSON
    if ($c->save_category_state($page_key, $category_title, $state)) {
        return $c->render(json => { success => 1 });
    } else {
        return $c->render(json => { error => 'Failed to save state' }, status => 500);
    }
}

# Toggles public/private visibility state of a stash page via AJAX.
# Route: POST /api/v1/stash/toggle-public
# Parameters (JSON):
#   page_key : Page key for stash (must match /^[\w_\-.]+$/)
#   is_public : New public state (1 for public, 0 for private)
# Returns:
#   JSON response: { success: 1, page_key: '...', is_public: 1 } on success
#   JSON error: { error: '...' } with status code on failure
# Behavior:
#   - Validates authentication and demo user status
#   - Validates page key format and required parameters
#   - Calls helper to toggle visibility flag in database
#   - Returns success confirmation with updated state or error message
sub toggle_public {
    my $c = shift;
    
    # Verify user authentication
    return $c->render(json => { error => 'Unauthorized' }, status => 401)
        unless $c->is_logged_in;
    
    # Block demo users from modifying public status
    return $c->render(json => { error => 'Demo account cannot modify public status' }, status => 403)
        if $c->is_demo;
    
    # Get JSON request body
    my $data = $c->req->json;
    my $page_key = $data->{page_key};
    my $is_public = $data->{is_public};
    
    # Validate required parameters
    unless (defined $page_key && defined $is_public) {
        return $c->render(json => { error => 'Missing required parameters' }, status => 400);
    }
    
    # Validate page key format for security
    return $c->render(json => { error => 'Invalid page name' }, status => 400)
        unless $page_key =~ /^[\w_\-.]+$/;
    
    # Call helper to toggle visibility in database
    if ($c->toggle_stash_public($page_key, $is_public)) {
        return $c->render(json => {
            success => 1,
            page_key => $page_key,
            is_public => $is_public ? 1 : 0
        });
    } else {
        return $c->render(json => { error => 'Failed to update visibility' }, status => 500);
    }
}

# Exports all user's stash data as a downloadable JSON file.
# Route: GET /stash/data/export
# Parameters: none (must be logged in)
# Returns: JSON file for user backup
sub export {
    my $c = shift;
    return $c->redirect_to('/login') unless $c->is_logged_in;

    my $unified_data = $c->get_unified_stash_data(); # Retrieve stash config
    my $json = JSON->new->pretty;
    my $json_string = $json->encode($unified_data);

    $c->res->headers->content_disposition('attachment; filename="stash_backup.json"');
    $c->res->headers->content_type('application/json');
    $c->render(data => $json_string);
}

# Imports stash data from uploaded JSON file.
# Route: POST /stash/data/import
# Parameters:
#   import_file : Uploaded JSON file from user containing stash data
# Returns: Redirects on success, error alert on failure/validation
sub import {
    my $c = shift;
    return $c->redirect_to('/login') unless $c->is_logged_in;

    # Block demo users from importing data
    return $c->alert('Demo account cannot import data.', 403) if $c->is_demo;
        
    my $upload = $c->param('import_file');
    
    # Validate file upload
    unless ($upload && $upload->size > 0) {
        return $c->alert('No file uploaded or file is empty.', 400);
    }
    
    # Read uploaded file content
    my $json_text;
    eval {
        $json_text = $upload->asset->slurp;
    };
    if ($@) {
        $c->app->log->error("Error reading uploaded file: $@");
        return $c->alert('Failed to read file content.', 400);
    }
    
    # Parse and validate JSON structure
    my $unified_data;
    eval { $unified_data = decode_json($json_text); };
    if (my $error = $@) {
        $c->app->log->error("Error decoding JSON: $error");
        return $c->alert('Invalid JSON file format.', 400);
    }
    
    # Validate stash data structure (must contain 'stashes' key).
    unless (ref $unified_data eq 'HASH' &&
            exists $unified_data->{stashes} &&
            ref $unified_data->{stashes} eq 'HASH') {
        return $c->alert('Invalid stash data structure. Missing or malformed "stashes" key.', 400);
    }
    
    # Save imported data to database for current user.
    my $user_id = $c->current_user_id;
    eval { $c->db->save_unified_stashes($user_id, $unified_data); };
    if (my $error = $@) {
        $c->app->log->error("Failed to save imported stash data: $error");
        return $c->alert("Error saving imported data: $error", 500);
    }
    
    return $c->redirect_to('/stash');
}

sub search {
    my $c = shift;
    
    return $c->render(json => { error => 'Unauthorized' }, status => 401) 
        unless $c->is_logged_in;
    
    my $query = $c->param('q') || '';
    $query = lc($query);
    
    return $c->render(json => { error => 'Query too short', results => [] }) 
        if length($query) < 2;
    
    my $unified_data = $c->get_unified_stash_data();
    my $stashes = $unified_data->{stashes} || {};
    
    my @results;
    
    for my $page_key (keys %$stashes) {
        my $stash_data = $stashes->{$page_key};
        my $categories = $stash_data->{categories} || [];
        
        for my $category (@$categories) {
            my $links = $category->{links} || [];
            
            for my $link (@$links) {
                my $name = lc($link->{name} || '');
                my $url = lc($link->{url} || '');
                
                if ($name =~ /\Q$query\E/ || $url =~ /\Q$query\E/) {
                    push @results, {
                        name  => $link->{name},
                        url   => $link->{url},
                        icon  => $link->{icon} || '',
                        stash => $page_key
                    };
                }
            }
        }
    }
    
    $c->render(json => { results => \@results });
}

1;

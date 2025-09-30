# /lib/MyApp/Controller/Stash/Pages.pm

package MyApp::Controller::Stash::Pages;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw(decode_json encode_json);

# Controller for stash page management operations.
# Responsibilities:
# - Handles permanent deletion of stash pages with data cleanup
# - Manages page renaming with conflict detection and validation
# - Provides page cloning functionality with deep copy operations
# - Offers API endpoint for retrieving user's page listings
# Integration points:
# - Uses authentication helpers (is_logged_in, current_user_id) for security
# - Integrates with unified stash data helpers for page operations
# - Depends on JSON encoding/decoding for deep copy operations

# Delete stash page permanently with data cleanup.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Redirect to login if not authenticated, redirect to stash on completion.
sub delete {
    my $c = shift;
    # Enforce user authentication for page deletion
    return $c->redirect_to('/login') unless $c->is_logged_in;
    
    # Extract page identifier from request parameters
    my $page_key = $c->param('page_key');          # Page key to delete
    return $c->redirect_to('/stash') unless $page_key;
    
    # Load user's stash data and remove specified page
    my $user_id = $c->current_user_id;             # Current user ID for ownership
    my $unified = $c->get_unified_stash_data();    # User's complete stash structure
    
    # Remove page from unified stash data structure
    delete $unified->{stashes}{$page_key};         # Delete page from stash collection
    $c->db->save_unified_stashes($user_id, $unified);  # DB: persist updated stash data
    
    return $c->redirect_to("/stash");              # Redirect to main stash view
}


# Rename existing stash page with validation and conflict checking.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Redirect to login if not authenticated, alert on error, redirect to stash on success.
sub rename {
    my $c = shift;
    # Enforce user authentication for page renaming
    return $c->redirect_to('/login') unless $c->is_logged_in;

    # Extract rename parameters from form submission
    my $old_name = $c->param('old_page_name');     # Current page name
    my $new_name = $c->param('new_page_name');     # Desired new page name
    
    # Validate required parameters presence
    return $c->alert('Missing parameters.', 400) unless $old_name && $new_name;
    
    # Validate new page name format for security and compatibility
    return $c->alert('Invalid page name format.', 400) 
        unless $new_name =~ /^[\w_\-.]+$/;
    
    # Load user's stash data for rename operation
    my $user_id = $c->current_user_id;             # Current user ID for ownership
    my $unified = $c->get_unified_stash_data();    # User's complete stash structure

    # Check for naming conflicts before proceeding with rename
    return $c->alert("Page '$new_name' already exists.", 409) 
        if exists $unified->{stashes}{$new_name};
    
    # Verify source page exists before attempting rename
    return $c->alert("Page '$old_name' not found.", 404) 
        unless exists $unified->{stashes}{$old_name};
    
    # Execute rename operation by moving data to new key
    $unified->{stashes}{$new_name} = delete $unified->{stashes}{$old_name};  # Atomic rename
    $c->db->save_unified_stashes($user_id, $unified);  # DB: persist renamed page
    
    return $c->redirect_to('/stash');              # Redirect to updated stash view
}


# Clone existing stash page with deep copy and validation.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Redirect to login if not authenticated, alert on error, redirect to edit on success.
sub clone { 
    my $c = shift;
    # Enforce user authentication for page cloning
    return $c->redirect_to('/login') unless $c->is_logged_in;

    # Extract cloning parameters from form submission
    my $source_name = $c->param('source_page_name'); # Source page to clone
    my $new_name = $c->param('new_page_name');        # Name for cloned page
    
    # Validate required parameters presence
    return $c->alert('Missing parameters.', 400) unless $source_name && $new_name;
    
    # Validate new page name format for security and compatibility
    return $c->alert('Invalid page name format.', 400) 
        unless $new_name =~ /^[\w_\-.]+$/;
        
    # Load user's stash data for cloning operation
    my $user_id = $c->current_user_id;             # Current user ID for ownership
    my $unified = $c->get_unified_stash_data();    # User's complete stash structure

    # Check for naming conflicts before proceeding with clone
    return $c->alert("Page '$new_name' already exists.", 409) 
        if exists $unified->{stashes}{$new_name};
    
    # Verify source page exists before attempting clone
    return $c->alert("Source page '$source_name' not found.", 404) 
        unless exists $unified->{stashes}{$source_name};

    # Create deep copy using JSON encode/decode to prevent reference sharing
    $unified->{stashes}{$new_name} = decode_json(encode_json($unified->{stashes}{$source_name}));
    $c->db->save_unified_stashes($user_id, $unified);  # DB: persist cloned page
    
    return $c->redirect_to("/edit?n=$new_name");   # Redirect to edit cloned page
}


# API endpoint for retrieving user's stash page listings.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   JSON response with pages array or error status.
sub list { 
    my $c = shift;
    # Enforce authentication for page listing API
    return $c->render(json => { error => 'Unauthorized' }, status => 401) unless $c->is_logged_in; 
    
    # Retrieve all page names for current user
    my $page_names = $c->get_all_page_names();     # Helper: get user's page list
    $c->render(json => { pages => $page_names });  # Return JSON array of page names
}


1;

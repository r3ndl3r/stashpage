# /lib/MyApp/Controller/Stash/Pages.pm

package MyApp::Controller::Stash::Pages;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw(decode_json encode_json);
use Mojo::Util qw(hmac_sha1_sum);

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

    # Don't allow deletion from demo account.
    return if $c->is_demo;  # Just redirect, no alert

    
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
    return $c->alert('Demo account cannot rename pages.', 403) if $c->is_demo;

    # Extract rename parameters from form submission
    my $old_name  = $c->param('old_page_name');     # Current page name (alias)
    my $new_name  = $c->param('new_page_name');     # Desired new alias (URL identifier)
    my $new_title = $c->param('new_title');         # Desired new display title
    
    # Validate required parameters presence
    return $c->alert('Missing parameters.', 400) unless $old_name && ($new_name || defined $new_title);
    
    # Validate new page name format for security and compatibility (only if alias is changing)
    if ($new_name && $new_name ne $old_name) {
        return $c->alert('Invalid page name format.', 400) 
            unless $new_name =~ /^[\w_\-.]+$/;
    }
    
    # Load user's stash data for rename operation
    my $user_id = $c->current_user_id;             # Current user ID for ownership
    my $unified = $c->get_unified_stash_data();    # User's complete stash structure

    # Verify source page exists before attempting rename
    return $c->alert("Page '$old_name' not found.", 404) 
        unless exists $unified->{stashes}{$old_name};

    # If alias is changing, handle the key move
    if ($new_name && $new_name ne $old_name) {
        # Check for naming conflicts before proceeding with move
        return $c->alert("Page '$new_name' already exists.", 409) 
            if exists $unified->{stashes}{$new_name};
            
        # Atomic key move
        $unified->{stashes}{$new_name} = delete $unified->{stashes}{$old_name};
        $old_name = $new_name; # Continue with new alias for title update
    }

    # Update the title field if provided (supports spaces and emojis)
    if (defined $new_title) {
        $unified->{stashes}{$old_name}{title} = $new_title;
    }

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
    return $c->alert('Demo account cannot create new pages.', 403) if $c->is_demo;

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


# Controller for stash page management operations.
# Responsibilities:
# - Handles permanent deletion of stash pages with data cleanup
# - Manages page renaming with conflict detection and validation
# - Provides page cloning functionality with deep copy operations
# - Provides interface and logic for custom page reordering
# - Offers API endpoint for retrieving user's page listings

# Display the interface for reordering stash pages.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   Redirect to login if not authenticated, reorder template render on success.
sub reorder_view {
    my $c = shift;
    # Enforce user authentication for reordering access
    return $c->redirect_to('/login') unless $c->is_logged_in;
    
    # Retrieve hierarchical dashboard structure for the UI
    $c->stash(dashboard_structure => $c->get_dashboard_structure());
    $c->render(template => 'reorder');
}


# Persist a new custom sequence for stash pages.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   JSON response with success or error status.
sub save_reorder {
    my $c = shift;
    # Enforce authentication and block demo account modifications
    return $c->render(json => { error => 'Unauthorized' }, status => 401) unless $c->is_logged_in;
    return $c->render(json => { error => 'Demo account restriction' }, status => 403) if $c->is_demo;

    # Extract ordered array of names from JSON payload
    my $order_list = $c->req->json; # Expects: ["lab", "swin", "links", "Movies"]
    my $user_id = $c->current_user_id;
    my $unified = $c->get_unified_stash_data();

    # Inject numeric 'order' weight into each stash object based on new position
    my $weight = 0;
    foreach my $name (@$order_list) {
        if (exists $unified->{stashes}{$name}) {
            $unified->{stashes}{$name}{order} = ++$weight;
        }
    }

    # Integration: DB helper for updated configuration persistence
    $c->db->save_unified_stashes($user_id, $unified);
    return $c->render(json => { success => 1 });
}


# Persist a new hierarchical structure for the dashboard.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   JSON response with success or error status.
sub api_save_structure {
    my $c = shift;
    # Enforce authentication and block demo account modifications
    return $c->render(json => { error => 'Unauthorized' }, status => 401) unless $c->is_logged_in;
    return $c->render(json => { error => 'Demo account restriction' }, status => 403) if $c->is_demo;

    # Extract structured data from JSON payload
    my $structure = $c->req->json; # Expects: [{id: "...", title: "...", stashes: [...]}, ...]
    
    if ($c->save_dashboard_structure($structure)) {
        return $c->render(json => { success => 1 });
    }
    
    return $c->render(json => { error => 'Failed to save dashboard structure' }, status => 500);
}


# Add a new category to the user's dashboard.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   JSON response with new category ID and title.
sub add_category {
    my $c = shift;
    return $c->render(json => { error => 'Unauthorized' }, status => 401) unless $c->is_logged_in;
    return $c->render(json => { error => 'Demo account restriction' }, status => 403) if $c->is_demo;

    my $title = $c->param('title') || 'New Category';
    my $id = 'cat_' . Mojo::Util::hmac_sha1_sum(time() . rand(), 'stash');
    
    my $structure = $c->get_dashboard_structure();
    push @$structure, {
        id => $id,
        title => $title,
        stashes => [],
        collapsed => 0
    };
    
    if ($c->save_dashboard_structure($structure)) {
        return $c->render(json => { success => 1, id => $id, title => $title });
    }
    
    return $c->render(json => { error => 'Failed to add category' }, status => 500);
}


# Rename an existing dashboard category.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   JSON response with success status.
sub rename_category {
    my $c = shift;
    return $c->render(json => { error => 'Unauthorized' }, status => 401) unless $c->is_logged_in;
    return $c->render(json => { error => 'Demo account restriction' }, status => 403) if $c->is_demo;

    my $id = $c->param('id');
    my $new_title = $c->param('title');
    
    return $c->render(json => { error => 'Missing parameters' }, status => 400) unless $id && $new_title;
    
    my $structure = $c->get_dashboard_structure();
    my $found = 0;
    foreach my $cat (@$structure) {
        if ($cat->{id} eq $id) {
            $cat->{title} = $new_title;
            $found = 1;
            last;
        }
    }
    
    if ($found && $c->save_dashboard_structure($structure)) {
        return $c->render(json => { success => 1 });
    }
    
    return $c->render(json => { error => 'Category not found or save failed' }, status => 404);
}


# Delete a dashboard category.
# Parameters:
#   $c : Mojolicious controller (calling context).
# Returns:
#   JSON response with success status.
sub delete_category {
    my $c = shift;
    return $c->render(json => { error => 'Unauthorized' }, status => 401) unless $c->is_logged_in;
    return $c->render(json => { error => 'Demo account restriction' }, status => 403) if $c->is_demo;

    my $id = $c->param('id');
    return $c->render(json => { error => 'Missing category ID' }, status => 400) unless $id;
    
    my $structure = $c->get_dashboard_structure();
    my @new_structure = grep { $_->{id} ne $id } @$structure;
    
    if ($c->save_dashboard_structure(\@new_structure)) {
        return $c->render(json => { success => 1 });
    }
    
    return $c->render(json => { error => 'Failed to delete category' }, status => 500);
}


1;

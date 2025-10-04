# /lib/MyApp/Controller/Stash/Display.pm

package MyApp::Controller::Stash::Display;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw(decode_json encode_json);

# Controller for stash viewing and editing interfaces.
# Responsibilities:
#   - Render the main stash index or a specific stash page in view mode.
#   - Render the edit interface for a specific page with drag-and-drop.
# Dependencies and integration:
#   - Requires authentication helpers (is_logged_in, is_admin).
#   - Uses helpers: get_all_page_names, get_stash_page_for_render,
#     get_unified_stash_data, get_empty_stash, and DB save_unified_stashes.
#   - Templates: 'stash' (view mode) and 'edit' (edit mode).

# Render the main stash page or a specific page when 'n' is provided.
# Route: GET /, GET /stash
# Params:
# - n (optional): page key string used to load a specific stash.
# - u (optional): username for public stash access.
# Behavior:
# - With 'u' and 'n' => public view (no authentication required).
# - No 'n' => render index hub listing available pages (requires auth).
# - With 'n' only => validate key, load categories, render specific page (requires auth).
sub index {
    my $c = shift;
    
    # Check if this is a public stash request (has u= and n= parameters)
    my $public_username = $c->param('u');  # Username parameter for public view
    my $public_page_key = $c->param('n');  # Stash page name parameter
    
    # PUBLIC STASH VIEW: Handle unauthenticated public stash access
    if ($public_username && $public_page_key) {
        # Validate username format (alphanumeric, underscore, hyphen only)
        return $c->alert('Invalid username.', 400) unless $public_username =~ /^[\w\-]+$/;
        
        # Validate page key format for safety
        return $c->alert('Invalid page name.', 400) unless $public_page_key =~ /^[\w_\-.]+$/;
        
        # Get user ID from username using database lookup
        my $user_id = $c->db->get_user_id($public_username);
        return $c->alert('User not found.', 404) unless $user_id;
        
        # Get the user's unified stash data from database
        my $unified = $c->db->get_unified_stashes($user_id);
        return $c->alert('Stash not found.', 404) unless $unified && ref($unified) eq 'HASH';
        
        # Check if the specific page exists in the user's stashes
        my $stash_data = $unified->{stashes}{$public_page_key};
        return $c->alert('Page not found.', 404) unless $stash_data;
        
        # Check if page is marked as public (is_public flag must be set to 1)
        my $is_public = $stash_data->{is_public} || 0;
        return $c->alert('This stash is not public.', 403) unless $is_public;
        
        # Transform links to items for template compatibility
        my $categories = $stash_data->{categories} || [];
        for my $category (@$categories) {
            $category->{items} = $category->{links} || [];
            $category->{x} = $category->{positions}{geometry}{x} || 0;
            $category->{y} = $category->{positions}{geometry}{y} || 0;
            $category->{collapsed} = $category->{positions}{collapsed} || 0;
        }

        # Render the public stash view (read-only, no edit controls)
        $c->stash(
            is_logged_in => 0,               # Not logged in (public view)
            is_admin => 0,                   # Not admin
            resolution => 'default',
            categories => $categories,
            page_key => $public_page_key,
            show_index_page => 0,
            is_public_view => 1,             # This is read-only public view
            is_public => 1                   # Stash is public (allowed this access)
        );
        
        return $c->render('stash');
    }
    
    # AUTHENTICATED VIEW: Normal logged-in user viewing their own stash
    return $c->redirect_to('/login') unless $c->is_logged_in; # Require authentication
    
    my $page_key = $c->param('n'); # Optional page key to load
    
    # Baseline UI flags for templates (auth state and layout hints)
    $c->stash(
        is_logged_in => $c->is_logged_in,
        is_admin => $c->is_admin,
        resolution => 'default'
    );
    
    my $page_names = $c->get_all_page_names(); # Retrieve available page names
    
    # If no page selected, render the index hub
    if (!$page_key) {
        $c->stash(
            page_names => $page_names,
            show_index_page => 1,
            categories => [],
            page_key => ''
        );
        return $c->render('stash'); # Index hub view
    }
    
    # Validate the requested page key format for safety
    return $c->alert('Invalid page name.', 400)
        unless $page_key =~ /^[\w_\-.]+$/; # Allow letters, digits, _, -, .
    
    # Fetch normalized category data for rendering the selected page
    my $categories = $c->get_stash_page_for_render($page_key);

    # If page missing, return to index hub
    unless (defined $categories) {
        return $c->redirect_to('/stash'); # Fallback to index
    }

    # Get the unified stash data to extract is_public flag
    my $unified = $c->get_unified_stash_data();
    my $is_public = $unified->{stashes}{$page_key}{is_public} || 0;

    # Provide data to template and render selected page
    $c->stash(
        categories => $categories,
        page_key => $page_key,
        show_index_page => 0,
        is_public => $is_public,
        is_public_view => 0
    );

    $c->render('stash'); # Specific page view
}

# Render the stash page in edit mode with drag-and-drop capabilities.
# Route: GET /edit
# Params:
#   - n (required): page key string to edit.
# Behavior:
#   - Validates 'n'; initializes empty page if not present; renders edit UI.
sub edit {
    my $c = shift;
    my $page_key = $c->param('n');                             # Page key to edit.

    return $c->redirect_to('/login') unless $c->is_logged_in;  # Require authentication.

    # Validate page key format and presence.
    return $c->alert('Invalid page name.', 400)
        unless $page_key =~ /^[\w_\-.]+$/;                     # Format guard.
    return $c->alert('Page name is required.', 400) unless $page_key;

    # Try to load categories for the requested page.
    my $categories = $c->get_stash_page_for_render($page_key);

    # If page does not exist, initialize a new one for this user.
    unless (defined $categories) {
        # Block demo users from creating new pages
        return $c->alert('Demo account cannot create new pages.', 403) if $c->is_demo;

        my $user_id = $c->current_user_id;                     # Target user id for ownership.
        my $unified = $c->get_unified_stash_data();            # Entire stash structure.

        # Create an empty page structure and persist it.
        $unified->{stashes}{$page_key} = { categories => $c->get_empty_stash() };
        $c->db->save_unified_stashes($user_id, $unified);      # Persist newly created page.
        $categories = $c->get_stash_page_for_render($page_key);# Reload canonical categories.
    }

    # Provide data for edit UI and render template.
    $c->stash(
        categories => $categories,
        page_key   => $page_key,
        resolution => 'default'
    );
    $c->render('edit');                                        # Edit mode view.
}

1;

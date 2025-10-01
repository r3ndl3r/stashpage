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
#   - n (optional): page key string used to load a specific stash.
# Behavior:
#   - No 'n' => render index hub listing available pages.
#   - With 'n' => validate key, load categories, render specific page.
sub index {
    my $c = shift;
    return $c->redirect_to('/login') unless $c->is_logged_in;  # Require authentication.

    my $page_key = $c->param('n');                             # Optional page key to load.

    # Baseline UI flags for templates (auth state and layout hints).
    $c->stash(
        is_logged_in => $c->is_logged_in,
        is_admin     => $c->is_admin,
        resolution   => 'default'
    );

    my $page_names = $c->get_all_page_names();                 # Retrieve available page names.

    # If no page selected, render the index hub.
    if (!$page_key) {
        $c->stash(
            page_names      => $page_names,
            show_index_page => 1,
            categories      => [],
            page_key        => ''
        );
        return $c->render('stash');                            # Index hub view.
    }

    # Validate the requested page key format for safety.
    return $c->alert('Invalid page name.', 400)
        unless $page_key =~ /^[\w_\-.]+$/;                     # Allow letters, digits, _, -, .

    # Fetch normalized category data for rendering the selected page.
    my $categories = $c->get_stash_page_for_render($page_key);

    # If page missing, return to index hub.
    unless (defined $categories) {
        return $c->redirect_to('/stash');                      # Fallback to index.
    }

    # Provide data to template and render selected page.
    $c->stash(
        categories      => $categories,
        page_key        => $page_key,
        show_index_page => 0
    );
    $c->render('stash');                                       # Specific page view.
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

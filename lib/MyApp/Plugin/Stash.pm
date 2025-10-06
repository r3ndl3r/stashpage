# /lib/MyApp/Plugin/Stash.pm

package MyApp::Plugin::Stash;

use Mojo::Base 'Mojolicious::Plugin', -signatures;
use strict;
use warnings;
use Mojo::JSON qw(decode_json encode_json);

# Dashboard bookmark management system plugin for stash application.
# Responsibilities:
# - Provides hierarchical bookmark organization with drag-and-drop positioning
# - Manages data persistence and retrieval for dashboard configurations
# - Handles new user initialization with default bookmark content
# - Implements category state management for UI collapse functionality
# - Offers data validation and transformation between storage and render formats
# Integration points:
# - Uses DB helpers for unified stash data persistence and retrieval
# - Integrates with authentication system for user-specific data scoping
# - Connects to JSON utilities for deep copying and data transformation

# Default dashboard configuration for new user initialization
my $DEFAULT_STASH = {
    stashes => {
        links => {
            categories => [
                {
                    title => "Essentials",                     # Essential services category
                    icon => "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/google.png",
                    baseUrl => "",
                    links => [
                        { name => "Google", url => "https://www.google.com", icon => "https://www.google.com/s2/favicons?domain=www.google.com" },
                        { name => "Reddit", url => "https://www.reddit.com", icon => "https://www.google.com/s2/favicons?domain=www.reddit.com" },
                        { name => "GitHub", url => "https://github.com/7d-technology/stashpage", icon => "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/github.png" },
                        { name => "Amazon", url => "https://www.amazon.com.au", icon => "https://www.google.com/s2/favicons?domain=www.amazon.com.au" },
                    ],
                    positions => { collapsed => 0, geometry => { x => 1520, y => 1120 } },
                },
                {
                    title => "Media",                          # Media services category
                    icon => "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/youtube.png",
                    baseUrl => "",
                    links => [
                        { name => "YouTube", url => "https://www.youtube.com", icon => "https://www.google.com/s2/favicons?domain=www.youtube.com" },
                        { name => "Twitch", url => "https://www.twitch.tv", icon => "https://www.google.com/s2/favicons?domain=www.twitch.tv" },
                        { name => "Torrent Client", url => "http://10.0.1.1:8888/", icon => "https://upload.wikimedia.org/wikipedia/commons/thumb/6/66/New_qBittorrent_Logo.svg/1024px-New_qBittorrent_Logo.svg.png" },
                    ],
                    positions => { collapsed => 0, geometry => { x => 2200, y => 1120 } },
                },
                {
                    title => "Homelab Tools",                  # Homelab management category
                    icon => "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/docker.png",
                    baseUrl => "",
                    links => [
                        { name => "Proxmox", url => "https://10.0.1.2:8006/#v1:0:18:4:::::::", icon => "https://img.icons8.com/color/600/proxmox.png" },
                        { name => "Uptime Kuma", url => "http://10.0.1.5:3001/dashboard", icon => "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/webp/uptime-kuma.webp" },
                        { name => "AdGuard", url => "http://10.0.1.6/", icon => "https://w7.pngwing.com/pngs/889/893/png-transparent-adguard-thumbnail.png" },
                    ],
                    positions => { collapsed => 0, geometry => { x => 1860, y => 1120 } },
                },
            ]
        }
    }
};

# Register stash management helpers with the application.
# Parameters:
#   $self   : Instance of plugin.
#   $app    : Mojolicious app object.
#   $config : Hashref of configuration overrides (optional).
# Returns:
#   None. Registers stash helpers in $app.
sub register ($self, $app, $config = {}) {
    # Configuration defaults for positioning and validation behavior
    my $default_position_x = $config->{default_position_x} || 50;           # Default X coordinate
    my $default_position_y = $config->{default_position_y} || 50;           # Default Y coordinate
    my $max_categories_per_page = $config->{max_categories_per_page} || 50; # Category limit per page
    my $enable_position_validation = $config->{enable_position_validation} // 1; # Position validation flag

    # Helper: get_unified_stash_data
    # Retrieves complete dashboard configuration for current user.
    # Parameters:
    #   $c : Mojolicious controller (calling context).
    # Returns:
    #   Hashref: unified stash structure or empty structure for unauthenticated users.
    $app->helper(get_unified_stash_data => sub ($c) {
        # Get current user identifier for data scoping
        my $user_id = $c->current_user_id;           # Current user database ID
        
        # Return empty structure for unauthenticated users
        return { stashes => {} } unless $user_id;
        
        # Integration: DB helper for complete stash data retrieval
        return $c->db->get_unified_stashes($user_id); # DB: fetch user's stash configuration
    });

    # Helper: get_stash_page_for_render
    # Transforms database format to render-optimized category structure.
    # Parameters:
    #   $c         : Mojolicious controller (calling context).
    #   $page_name : Name of page to retrieve for rendering.
    # Returns:
    #   Arrayref: render-ready category data or undef if page not found.
    $app->helper(get_stash_page_for_render => sub ($c, $page_name) {
        # Retrieve user's complete stash configuration
        my $unified = $c->get_unified_stash_data();
        
        # Return undefined for non-existent pages
        return undef unless exists $unified->{stashes}{$page_name};
        
        # Extract specific page data from unified structure
        my $page_data = $unified->{stashes}{$page_name};
        
        # Transform database format to render-ready structure
        my @categories;
        foreach my $cat (@{$page_data->{categories} || []}) {
            # Apply default positioning for missing geometry data
            my $geometry = $cat->{positions}{geometry} 
                        || { x => $default_position_x, y => $default_position_y };
            
            # Create flattened category structure for template system
            push @categories, {
                title => $cat->{title},
                icon => $cat->{icon},
                items => $cat->{links},                         # Bookmark array
                x => $geometry->{x},                            # X position
                y => $geometry->{y},                            # Y position  
                collapsed => $cat->{positions}{collapsed} || 0, # Collapse state
                baseUrl => $cat->{baseUrl} || '',               # URL prefix
                color => $cat->{color} // '#3b82f6'
            };
        }
        
        # Sort categories by X coordinate (left-to-right), then Y (top-to-bottom)
        # Ensures mobile view displays in column-by-column reading order
        @categories = sort { $a->{x} <=> $b->{x} || $a->{y} <=> $b->{y} } @categories;

        return \@categories;                                   # Template-ready data
    });

    # Helper: save_stash_page_data
    # Persists dashboard modifications with validation and format conversion.
    # Parameters:
    #   $c            : Mojolicious controller (calling context).
    #   $page_key     : Page identifier for data storage.
    #   $new_data_ref : Arrayref of category data in render format.
    # Returns:
    #   Boolean: success status of save operation.
    $app->helper(save_stash_page_data => sub ($c, $page_key, $new_data_ref) {
        # Verify user authentication for data modification
        my $user_id = $c->current_user_id;
        return 0 unless $user_id;

        # Block demo user from saving stash data
        return 0 if $c->is_demo;

        # Validate input data structure and limits
        return 0 unless ref($new_data_ref) eq 'ARRAY';
        return 0 if $max_categories_per_page > 0 && @$new_data_ref > $max_categories_per_page;

        # Load current configuration for modification
        my $unified = $c->get_unified_stash_data();
        my @new_categories;

        # Transform render format to database storage format
        foreach my $new_cat (@$new_data_ref) {
            # Validate required category fields
            next unless defined $new_cat->{title} && length($new_cat->{title});
            next unless ref($new_cat->{items}) eq 'ARRAY';

            # Extract and validate position coordinates
            my $x_pos = $new_cat->{x} || $default_position_x;
            my $y_pos = $new_cat->{y} || $default_position_y;

            # Apply position validation if enabled
            if ($enable_position_validation) {
                $x_pos = $x_pos < 0 ? 0 : $x_pos;
                $y_pos = $y_pos < 0 ? 0 : $y_pos;
            }

            # Validate and sanitize color format
            my $color = $new_cat->{color} || '#3b82f6';
            # Remove whitespace and convert to lowercase for validation
            $color =~ s/\s+//g;
            $color = lc($color);
            # Add # prefix if missing
            $color = '#' . $color unless $color =~ /^#/;
            # Validate hex format (6 characters after #)
            unless ($color =~ /^#[0-9a-f]{6}$/) {
                # Invalid format - reset to default blue
                $color = '#3b82f6';
            }

            my $positions = {
                collapsed => $new_cat->{collapsed} || 0,
                geometry => { x => $x_pos, y => $y_pos }
            };

            # Build complete category record
            push @new_categories, {
                title => $new_cat->{title},
                icon => $new_cat->{icon} // '',
                baseUrl => $new_cat->{baseUrl} // '',
                color => $color,
                links => $new_cat->{items},
                positions => $positions
            };
        }

        # Update unified structure with new data
        $unified->{stashes}{$page_key} = {
            categories => \@new_categories
        };

        # Integration: DB helper for data persistence
        return $c->db->save_unified_stashes($user_id, $unified); # DB: save updated configuration
    });

    # Helper: save_category_state
    # Updates individual category collapse state for UI persistence.
    # Parameters:
    #   $c               : Mojolicious controller (calling context).
    #   $page_key        : Page identifier containing the category.
    #   $category_title  : Title of category to update.
    #   $state          : New state ('collapsed' or 'expanded').
    # Returns:
    #   Boolean: success status of state update.
    $app->helper(save_category_state => sub ($c, $page_key, $category_title, $state) {
        # Verify user authentication for state modification
        my $user_id = $c->current_user_id;
        return 0 unless $user_id;

        # Block demo user from changing category state
        return 0 if $c->is_demo; 

        # Load current configuration for targeted update
        my $unified = $c->get_unified_stash_data();
        return 0 unless exists $unified->{stashes}{$page_key};
        
        # Locate and update specific category state
        my $updated = 0;
        foreach my $cat (@{$unified->{stashes}{$page_key}{categories}}) {
            if ($cat->{title} eq $category_title) {
                # Convert state to boolean for consistent storage
                $cat->{positions}{collapsed} = ($state eq 'collapsed') ? 1 : 0;
                $updated = 1;
                last;                                          # Exit after successful update
            }
        }
        
        # Return failure if category not found
        return 0 unless $updated;
        
        # Integration: DB helper for state persistence
        return $c->db->save_unified_stashes($user_id, $unified); # DB: save state change
    });

    # Helper: get_all_page_names
    # Provides sorted list of user's dashboard pages.
    # Parameters:
    #   $c : Mojolicious controller (calling context).
    # Returns:
    #   Arrayref: sorted page names for navigation.
    $app->helper(get_all_page_names => sub ($c) {
        # Retrieve user's complete stash configuration
        my $unified = $c->get_unified_stash_data();
        
        # Return sorted page names for consistent navigation
        return [ sort keys %{$unified->{stashes}} ];          # Alphabetically sorted names
    });

    # Helper: get_default_stash
    # Provides deep copy of default categories for new user initialization.
    # Parameters:
    #   $c : Mojolicious controller (calling context).
    # Returns:
    #   Arrayref: default category structure for new users.
    $app->helper(get_default_stash => sub ($c) {
        # Create deep copy to prevent reference sharing between users
        return decode_json(encode_json($DEFAULT_STASH->{stashes}->{links}->{categories}));
    });

    # Helper: initialize_default_stash_for_user
    # Sets up new user account with functional default dashboard.
    # Parameters:
    #   $c       : Mojolicious controller (calling context).
    #   $user_id : Database ID of new user account.
    # Returns:
    #   Boolean: success status of initialization.
    $app->helper(initialize_default_stash_for_user => sub ($c, $user_id) {
        # Generate fresh default categories for new user
        my $default_categories = $c->get_default_stash();      # Deep copy of defaults
        
        # Create complete stash structure with default 'links' page
        my $unified = {
            stashes => {
                'links' => {
                    categories => $default_categories
                }
            }
        };
        
        # Integration: DB helper for new user data persistence
        return $c->db->save_unified_stashes($user_id, $unified); # DB: save initial configuration
    });

    # Helper: get_empty_stash
    # Provides empty category structure for new page creation.
    # Parameters:
    #   $c : Mojolicious controller (calling context).
    # Returns:
    #   Arrayref: empty category array for new pages.
    $app->helper('get_empty_stash' => sub {
        my $c = shift;
        
        # Return empty array for new page initialization
        return [];                                             # Empty category structure
    });

    # Hook: after_startup
    # Logs plugin initialization and validates configuration.
    $app->hook(after_startup => sub ($app) {
        $app->log->info("Stash plugin initialized with default content and validation");
    });

    # Helper: toggle_stash_public
    # Toggles the public/private visibility state of a stash page.
    # Parameters:
    #   $c : Mojolicious controller (calling context).
    #   $page_key : Page identifier to toggle visibility for.
    #   $is_public : New public state (1 for public, 0 for private).
    # Returns:
    #   Boolean: success status of visibility update.
    $app->helper(toggle_stash_public => sub ($c, $page_key, $is_public) {
        # Verify user authentication for visibility modification
        my $user_id = $c->current_user_id;
        return 0 unless $user_id;
        
        # Block demo user from changing visibility
        return 0 if $c->is_demo;
        
        # Load current unified stash data
        my $unified = $c->get_unified_stash_data();
        return 0 unless exists $unified->{stashes}{$page_key};
        
        # Update the is_public flag in JSON structure
        $unified->{stashes}{$page_key}{is_public} = $is_public ? 1 : 0;
        
        # Integration: DB helper for data persistence
        return $c->db->save_unified_stashes($user_id, $unified);
    });

    # Helper: get_stash_emoji
    # Returns an emoji icon based on stash name with fuzzy matching.
    # Parameters:
    #   $c : Mojolicious controller (calling context).
    #   $page_name : Name of the stash page.
    # Returns:
    #   String: emoji character matching the stash name or default folder emoji.
    $app->helper(get_stash_emoji => sub ($c, $page_name) {
        # Emoji mapping based on keywords
        my %emoji_map = (
            # Media & Entertainment
            'media' => '🎬',
            'music' => '🎵',
            'videos' => '📹',
            'movies' => '🎥',
            'tv' => '📺',
            'shows' => '📺',
            'podcasts' => '🎙️',
            'podcast' => '🎙️',
            'streaming' => '📡',
            'youtube' => '▶️',
            
            # Reading & Learning
            'books' => '📚',
            'reading' => '📖',
            'articles' => '📰',
            'blog' => '✍️',
            'blogs' => '✍️',
            'wiki' => '📖',
            'documentation' => '📚',
            'tutorial' => '🎓',
            'tutorials' => '🎓',
            'education' => '🎓',
            'learning' => '📝',
            'study' => '📖',
            'courses' => '🎓',
            'course' => '🎓',
            'swin' => '🎓',
            
            # Work & Productivity
            'work' => '💼',
            'business' => '💼',
            'office' => '🏢',
            'job' => '💼',
            'career' => '📈',
            'meeting' => '🤝',
            'meetings' => '🤝',
            'calendar' => '📅',
            'schedule' => '🗓️',
            'tasks' => '✅',
            'todo' => '📋',
            'planning' => '📋',
            
            # Development & Tech
            'dev' => '💻',
            'code' => '⌨️',
            'development' => '👨‍💻',
            'programming' => '💻',
            'github' => '🐙',
            'git' => '🔀',
            'api' => '🔌',
            'database' => '🗄️',
            'server' => '🖥️',
            'cloud' => '☁️',
            'docker' => '🐳',
            'devops' => '⚙️',
            'linux' => '🐧',
            'terminal' => '⌨️',
            'shell' => '🐚',
            'lab' => '🐧',
            
            # Design & Creative
            'design' => '🎨',
            'art' => '🎨',
            'creative' => '🎨',
            'graphics' => '🖼️',
            'photos' => '📷',
            'photography' => '📸',
            'images' => '🖼️',
            'icons' => '🎯',
            'colors' => '🌈',
            'fonts' => '🔤',
            
            # Social & Communication
            'social' => '👥',
            'chat' => '💬',
            'messaging' => '💬',
            'email' => '📧',
            'mail' => '📮',
            'contacts' => '📇',
            'friends' => '👫',
            'community' => '🌐',
            
            # Shopping & Finance
            'shopping' => '🛒',
            'shop' => '🛍️',
            'store' => '🏪',
            'cart' => '🛒',
            'wishlist' => '⭐',
            'deals' => '💰',
            'finance' => '💰',
            'money' => '💵',
            'banking' => '🏦',
            'crypto' => '₿',
            'stocks' => '📈',
            'investing' => '💹',
            
            # Food & Lifestyle
            'food' => '🍔',
            'recipes' => '🍳',
            'cooking' => '👨‍🍳',
            'restaurant' => '🍽️',
            'restaurants' => '🍽️',
            'coffee' => '☕',
            'drinks' => '🍹',
            
            # Travel & Places
            'travel' => '✈️',
            'trips' => '🧳',
            'vacation' => '🏖️',
            'hotel' => '🏨',
            'hotels' => '🏨',
            'flights' => '✈️',
            'maps' => '🗺️',
            
            # Sports & Fitness
            'sports' => '⚽',
            'fitness' => '💪',
            'gym' => '🏋️',
            'workout' => '🏃',
            'health' => '🏥',
            'running' => '🏃',
            'cycling' => '🚴',
            'swimming' => '🏊',
            
            # Gaming
            'gaming' => '🎮',
            'games' => '🎯',
            'game' => '🕹️',
            'steam' => '🎮',
            'xbox' => '🎮',
            'playstation' => '🎮',
            'nintendo' => '🎮',
            
            # Tools & Resources
            'tools' => '🔧',
            'resources' => '📦',
            'utilities' => '🛠️',
            'apps' => '📱',
            'software' => '💿',
            'downloads' => '⬇️',
            
            # Projects & Ideas
            'projects' => '🚀',
            'project' => '🚀',
            'ideas' => '💡',
            'inspiration' => '✨',
            'brainstorm' => '🧠',
            
            # Organization
            'notes' => '📋',
            'docs' => '📄',
            'documents' => '📄',
            'files' => '📁',
            'archive' => '📦',
            'backup' => '💾',
            
            # General
            'links' => '🔗',
            'favorites' => '⭐',
            'bookmarks' => '🔖',
            'starred' => '⭐',
            'important' => '❗',
            'urgent' => '🚨',
            'personal' => '👤',
            'private' => '🔒',
            'public' => '🌍',
            
            # Science & Research
            'research' => '🔬',
            'science' => '🔬',
            'experiment' => '⚗️',
            'data' => '📊',
            'analytics' => '📈',
            
            # News & Information
            'news' => '📡',
            'tech' => '💻',
            'technology' => '🔌',
            'weather' => '🌤️',
        );
        
        my $lower = lc($page_name);
        
        # Exact match first
        return $emoji_map{$lower} if exists $emoji_map{$lower};
        
        # Fuzzy matching - check if name contains any keyword
        for my $keyword (keys %emoji_map) {
            return $emoji_map{$keyword} if $lower =~ /\b$keyword\b/;
        }
        
        return '📁';  # Default folder emoji
    });

}

1;

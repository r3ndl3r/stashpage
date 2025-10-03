// /js/search.js

/**
 * Global Cross-Stash Search Module
 * 
 * This module provides cross-stash search functionality allowing users to search
 * for bookmarks across all their stashes from the index page. Features include:
 * - Real-time search with debouncing to minimize API calls
 * - Keyboard shortcuts for quick access (Ctrl/Cmd + K, Escape)
 * - Visual result highlighting with stash context badges
 * - Click-to-open bookmark functionality
 * - Loading states and error handling
 * - Responsive search bar animations
 */

/**
 * Global Search Configuration
 * 
 * Controls search behavior, timing, and validation
 */
const SEARCH_CONFIG = {
    MIN_QUERY_LENGTH: 2,        // Minimum characters before triggering search
    DEBOUNCE_DELAY: 300,         // Milliseconds to wait after user stops typing
    API_ENDPOINT: '/api/search'  // Backend search API endpoint
};

/**
 * DOM Element References
 * 
 * Cached references to search UI elements for performance
 */
const elements = {
    toggle: document.getElementById('global-search-toggle'),
    container: document.getElementById('global-search-container'),
    input: document.getElementById('global-search-input'),
    clearBtn: document.getElementById('clear-global-search'),
    status: document.getElementById('global-search-status'),
    results: document.getElementById('global-search-results'),
    resultsList: document.getElementById('global-search-results-list')
};

/**
 * Search State Management
 * 
 * Tracks timing for debouncing search requests
 */
let searchTimeout = null;

/**
 * Global Search Initialization
 * 
 * Sets up event listeners and validates DOM elements
 * Only runs if search elements exist on the page (index page only)
 */
function initializeGlobalSearch() {
    // Verify search elements exist before initializing
    if (!elements.toggle || !elements.container) {
        return; // Not on index page - skip initialization
    }

    setupSearchEventListeners();
}

/**
 * Event Listener Setup
 * 
 * Attaches all event handlers for search functionality
 */
function setupSearchEventListeners() {
    // Toggle search bar visibility
    elements.toggle.addEventListener('click', toggleGlobalSearch);

    // Keyboard shortcuts for accessibility
    document.addEventListener('keydown', handleSearchKeyboard);

    // Real-time search with debouncing
    elements.input.addEventListener('input', handleSearchInput);

    // Clear search and reset state
    elements.clearBtn.addEventListener('click', clearGlobalSearch);
}

/**
 * Search Bar Toggle Handler
 * 
 * Shows or hides the search bar when magnifying glass icon is clicked
 */
function toggleGlobalSearch() {
    if (elements.container.classList.contains('hidden')) {
        openGlobalSearch();
    } else {
        closeGlobalSearch();
    }
}

/**
 * Open Global Search Bar
 * 
 * Reveals search input and sets focus for immediate typing
 */
function openGlobalSearch() {
    elements.container.classList.remove('hidden');
    elements.input.focus();
}

/**
 * Close Global Search Bar
 * 
 * Hides search interface and clears all state
 */
function closeGlobalSearch() {
    elements.container.classList.add('hidden');
    elements.input.value = '';
    elements.clearBtn.classList.add('hidden');
    clearSearchResults();
}

/**
 * Keyboard Shortcut Handler
 * 
 * Processes keyboard events for search shortcuts:
 * - Ctrl/Cmd + K: Open search bar
 * - Escape: Close search bar
 * 
 * @param {KeyboardEvent} e - Keyboard event object
 */
function handleSearchKeyboard(e) {
    // Open search with Ctrl/Cmd + K
    if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
        e.preventDefault();
        if (elements.container.classList.contains('hidden')) {
            openGlobalSearch();
        }
    }

    // Close search with Escape key
    if (e.key === 'Escape' && !elements.container.classList.contains('hidden')) {
        closeGlobalSearch();
    }
}

/**
 * Search Input Handler with Debouncing
 * 
 * Processes user input and triggers search after debounce delay
 * Manages clear button visibility and validates minimum query length
 * 
 * @param {Event} e - Input event object
 */
function handleSearchInput(e) {
    const query = e.target.value.trim();

    // Toggle clear button visibility
    if (query.length > 0) {
        elements.clearBtn.classList.remove('hidden');
    } else {
        elements.clearBtn.classList.add('hidden');
        clearSearchResults();
        return;
    }

    // Debounce search to avoid excessive API calls
    clearTimeout(searchTimeout);
    searchTimeout = setTimeout(() => {
        if (query.length >= SEARCH_CONFIG.MIN_QUERY_LENGTH) {
            performGlobalSearch(query);
        }
    }, SEARCH_CONFIG.DEBOUNCE_DELAY);
}

/**
 * Clear Search Handler
 * 
 * Resets search input and results, maintains focus
 */
function clearGlobalSearch() {
    elements.input.value = '';
    elements.clearBtn.classList.add('hidden');
    clearSearchResults();
    elements.input.focus();
}

/**
 * Perform Global Search via API
 * 
 * Sends search query to backend and processes results
 * Handles loading states and error conditions
 * 
 * @param {string} query - Search query string
 */
function performGlobalSearch(query) {
    showSearchLoading();

    fetch(`${SEARCH_CONFIG.API_ENDPOINT}?q=${encodeURIComponent(query)}`)
        .then(response => {
            if (!response.ok) throw new Error('Search request failed');
            return response.json();
        })
        .then(data => {
            displaySearchResults(data.results, query);
        })
        .catch(error => {
            console.error('Global search error:', error);
            showSearchError('Search failed. Please try again.');
        });
}

/**
 * Display Loading State
 * 
 * Shows spinner and status message while search is in progress
 */
function showSearchLoading() {
    elements.status.innerHTML = '<span class="global-search-loading"></span> Searching...';
    elements.results.classList.add('hidden');
}

/**
 * Display Error Message
 * 
 * Shows user-friendly error message when search fails
 * 
 * @param {string} message - Error message to display
 */
function showSearchError(message) {
    elements.status.textContent = message;
    elements.status.classList.add('text-red-400');
}

/**
 * Display Search Results
 * 
 * Renders search results or empty state message
 * Highlights matched text and shows stash context
 * 
 * @param {Array} results - Array of search result objects
 * @param {string} query - Original search query for highlighting
 */
function displaySearchResults(results, query) {
    elements.resultsList.innerHTML = '';
    elements.status.classList.remove('text-red-400');

    // Handle empty results
    if (!results || results.length === 0) {
        elements.status.textContent = 'No bookmarks found';
        elements.results.classList.add('hidden');
        return;
    }

    // Show result count
    const plural = results.length !== 1 ? 's' : '';
    elements.status.textContent = `Found ${results.length} bookmark${plural}`;
    elements.results.classList.remove('hidden');

    // Render each result item
    results.forEach(result => {
        const resultItem = createSearchResultItem(result, query);
        elements.resultsList.appendChild(resultItem);
    });
}

/**
 * Create Search Result Item Element
 * 
 * Builds HTML for a single search result with icon, name, URL, and stash badge
 * Each result is clickable and opens the bookmark in a new tab
 * 
 * @param {Object} result - Search result object {name, url, icon, stash}
 * @param {string} query - Search query for text highlighting
 * @returns {HTMLElement} Complete result item element
 */
function createSearchResultItem(result, query) {
    const item = document.createElement('div');
    item.className = 'global-search-result-item flex items-center gap-3';
    
    // Make entire item clickable
    item.onclick = () => window.open(result.url, '_blank');

    // Generate icon HTML with fallback for missing icons
    let iconHTML = '';
    if (result.icon) {
        iconHTML = `<img src="${result.icon}" class="global-search-icon" alt="">`;
    } else {
        iconHTML = `
            <div class="global-search-icon bg-gray-600 flex items-center justify-center">
                <svg class="w-4 h-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
                </svg>
            </div>
        `;
    }

    // Highlight matched text in bookmark name
    const highlightedName = highlightSearchMatch(result.name, query);

    // Build complete result item structure
    item.innerHTML = `
        ${iconHTML}
        <div class="flex-1 min-w-0">
            <div class="font-semibold text-white truncate">${highlightedName}</div>
            <div class="text-sm text-gray-400 truncate">${result.url}</div>
        </div>
        <span class="global-search-stash-badge">${result.stash}</span>
    `;

    return item;
}

/**
 * Highlight Matched Text in Search Results
 * 
 * Wraps matched query text in highlight span for visual emphasis
 * Case-insensitive matching with original case preservation
 * 
 * @param {string} text - Text to search and highlight in
 * @param {string} query - Query string to highlight
 * @returns {string} HTML string with highlighted matches
 */
function highlightSearchMatch(text, query) {
    const lowerText = text.toLowerCase();
    const lowerQuery = query.toLowerCase();
    const index = lowerText.indexOf(lowerQuery);
    
    // Return original text if no match found
    if (index === -1) return text;
    
    // Split text around match and wrap match in highlight span
    const before = text.substring(0, index);
    const match = text.substring(index, index + query.length);
    const after = text.substring(index + query.length);
    
    return `${before}<span class="global-search-highlight">${match}</span>${after}`;
}

/**
 * Clear Search Results and Status
 * 
 * Resets results display to empty state and clears status messages
 */
function clearSearchResults() {
    elements.resultsList.innerHTML = '';
    elements.results.classList.add('hidden');
    elements.status.textContent = '';
    elements.status.classList.remove('text-red-400');
}

// Initialize search when DOM is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeGlobalSearch);
} else {
    initializeGlobalSearch();
}

// /js/stash.js

/**
 * Stash Dashboard View Controller Module
 * 
 * This module handles the view-only dashboard functionality for displaying and
 * managing stash collections. It provides a comprehensive interface for users to
 * interact with their stash data including:
 * - Page navigation and creation with input validation
 * - Modal management for rename, clone, and import operations
 * - Dashboard auto-centering and responsive viewport behavior
 * - Category collapse/expand state management with server persistence
 * - Custom delete confirmation dialogs with visual feedback
 * - Dropdown menu management with exclusive visibility
 * - Keyboard shortcuts and accessibility features
 */

/**
 * Application Configuration Constants
 * 
 * These values control responsive behavior, timing, and validation rules
 * for the stash dashboard interface and user interactions
 */
const TOPBAR_HEIGHT = 50;                  // Height of navigation bar for viewport calculations
const MOBILE_BREAKPOINT = 768;             // Pixel threshold for mobile vs desktop behavior
const DASHBOARD_CENTER_X = 2000;           // Horizontal center point of dashboard canvas
const DASHBOARD_CENTER_Y = 1250;           // Vertical center point of dashboard canvas
const RESIZE_DEBOUNCE_DELAY = 150;         // Milliseconds to wait before processing resize
const FOCUS_CENTER_DELAY = 100;            // Delay before centering when window regains focus
const INITIAL_CENTER_DELAY = 100;          // Delay for initial dashboard centering
const PAGE_NAME_PATTERN = /^[\w-.]+$/;     // Allowed characters for page names (security)

/**
 * Global State Management
 * 
 * Centralized state variables for managing dashboard behavior and timing
 * These variables coordinate responsive behavior and async operations
 */
let resizeTimer;                           // Debounce timer for window resize events
window.pendingDeleteForm = null;           // Reference to form awaiting delete confirmation

/**
 * Page Navigation and Creation System
 * 
 * Validates user input for new page names and navigates to the edit interface
 * Implements security restrictions to prevent invalid URLs and dangerous characters
 * Always navigates to edit mode to enable immediate stash creation
 */
function goToPage() {
    const pageNameInput = document.getElementById('page-name-input');
    let pageName = pageNameInput.value.trim();
    
    // Validate that user provided a page name
    if (!pageName) {
        alert('Please enter a page name.');
        return;
    }
    
    // Security validation: restrict to safe characters for URLs and file systems
    if (!pageName.match(PAGE_NAME_PATTERN)) {
        alert('Invalid page name. Use only letters, numbers, underscores, and dashes.');
        return;
    }
    
    // Navigate to edit mode to enable immediate stash creation and editing
    let url = '/edit?n=' + encodeURIComponent(pageName);
    window.location.href = url;
}

/**
 * Stash Context Menu Management
 * 
 * Manages dropdown menus for individual stash items with exclusive visibility
 * Ensures only one menu is open at a time for better user experience and
 * prevents visual clutter from multiple overlapping menus
 * 
 * @param {string} stashName - The unique identifier/name of the stash whose 
 *                             menu should be toggled. Must match the stash name
 *                             used in the menu element ID (menu-{stashName})
 */
function toggleStashMenu(stashName) {
    // Close all other menus first to ensure only one menu is open at a time
    // This prevents UI clutter and provides consistent user experience
    document.querySelectorAll('[id^="menu-"]').forEach(menu => {
        if (menu.id !== `menu-${stashName}`) {
            menu.classList.add('hidden');
        }
    });
    
    // Toggle the visibility of the target menu using Tailwind's 'hidden' class
    const menu = document.getElementById(`menu-${stashName}`);
    if (menu) {
        menu.classList.toggle('hidden');
    }
}

/**
 * Rename Modal Management
 * 
 * Opens the rename dialog with the current page name pre-filled for editing
 * Provides immediate focus and text selection for optimal user experience
 * 
 * @param {string} pageName - Current name of the page to rename
 */
function openRenameModal(pageName) {
    // Pre-populate form fields with current values for easy editing
    document.getElementById('old_page_name').value = pageName;
    document.getElementById('new_page_name').value = pageName;
    
    const modal = document.getElementById('renameModal');
    modal.style.display = 'flex';  // Direct style manipulation instead of classes
    
    // Focus input and select all text for immediate editing convenience
    setTimeout(() => {
        document.getElementById('new_page_name').focus();
        document.getElementById('new_page_name').select();
    }, 100);
}

/**
 * Rename Modal Closure Handler
 * 
 * Closes the rename modal and cleans up any temporary UI state
 */
function closeRenameModal() {
    const modal = document.getElementById('renameModal');
    modal.style.display = 'none';  // Direct style manipulation
}

/**
 * Clone Modal Management
 * 
 * Opens the clone dialog with source page information and suggested clone name
 * Automatically generates a descriptive default name with "-copy" suffix
 * 
 * @param {string} pageName - Name of the page to clone
 */
function openCloneModal(pageName) {
    // Set up source page information for form submission
    document.getElementById('source_page_name').value = pageName;
    document.getElementById('source_page_display').textContent = pageName;
    
    // Generate suggested clone name with standard suffix
    document.getElementById('clone_new_page_name').value = `${pageName}-copy`;
    
    // Show modal and focus input for immediate editing
    const modal = document.getElementById('cloneModal');
    modal.style.display = 'flex';  // Direct style manipulation
    
    setTimeout(() => {
        document.getElementById('clone_new_page_name').focus();
        document.getElementById('clone_new_page_name').select();
    }, 100);
}

/**
 * Clone Modal Closure Handler
 * 
 * Closes the clone modal and cleans up any temporary UI state
 */
function closeCloneModal() {
    const modal = document.getElementById('cloneModal');
    modal.style.display = 'none';  // Direct style manipulation
}

/**
 * Import Modal Management
 * 
 * Opens the import dialog for uploading stash backup files from external sources
 * Provides interface for users to restore dashboard data from JSON exports
 */
function openImportModal() {
    const modal = document.getElementById('importModal');
    modal.style.display = 'flex';  // Direct style manipulation
}

/**
 * Import Modal Closure Handler
 * 
 * Closes the import modal and cleans up any file upload state
 */
function closeImportModal() {
    const modal = document.getElementById('importModal');
    modal.style.display = 'none';  // Direct style manipulation
}

/**
 * Dashboard Viewport Centering System
 * 
 * Centers the dashboard viewport on the main content area for optimal initial viewing
 * Calculates scroll position based on predefined content center point and current
 * viewport dimensions. Only used on desktop devices where full canvas navigation
 * provides value to the user experience
 */
function centerDashboardView() {
    const wrapper = document.getElementById('dashboard-wrapper');
    if (!wrapper) return;
    
    // Calculate scroll position to center content in current viewport
    const targetScrollLeft = DASHBOARD_CENTER_X - (window.innerWidth / 2);
    const targetScrollTop = DASHBOARD_CENTER_Y - (window.innerHeight / 2);
    
    // Apply scroll position with bounds checking to prevent negative scroll values
    wrapper.scrollLeft = Math.max(0, targetScrollLeft);
    wrapper.scrollTop = Math.max(0, targetScrollTop);
}

/**
 * Dashboard Initialization System
 * 
 * Sets up the complete dashboard interface including collapse states, responsive
 * behavior, and viewport management. Determines appropriate behavior based on
 * device capabilities and screen size
 */
function initializeDashboard() {
    // Apply saved collapse states from server data
    applyCollapseStates();
    
    // Only enable advanced dashboard features on desktop devices
    if (window.innerWidth > MOBILE_BREAKPOINT) {
        // Initial centering with delay to ensure DOM is fully rendered
        setTimeout(centerDashboardView, INITIAL_CENTER_DELAY);
        
        // Debounced resize handler to maintain centered view during window resizing
        window.addEventListener('resize', () => {
            clearTimeout(resizeTimer);
            resizeTimer = setTimeout(centerDashboardView, RESIZE_DEBOUNCE_DELAY);
        });
        
        // Re-center when window regains focus (handles tab switching scenarios)
        window.addEventListener('focus', () => {
            setTimeout(centerDashboardView, FOCUS_CENTER_DELAY);
        });
    }
}

/**
 * Category Collapse Icon Management
 * 
 * Updates the visual collapse/expand icon based on category state
 * Handles different DOM structures where icons might be located
 * 
 * @param {HTMLElement} header - The category header element containing the icon
 * @param {boolean} isCollapsed - Whether the category is currently collapsed
 */
function updateCollapseIcon(header, isCollapsed) {
    let collapseIcon = header.querySelector('.collapse-icon');
    
    // Fallback search if icon is not directly in header
    if (!collapseIcon) {
        const dragHandle = header.closest('.drag-handle');
        if (dragHandle) {
            collapseIcon = dragHandle.querySelector('.collapse-icon');
        }
    }
    
    if (!collapseIcon) {
        console.error('Collapse icon not found for header:', header);
        return;
    }
    
    // Update icon SVG based on collapsed state (right arrow for collapsed, down arrow for expanded)
    collapseIcon.innerHTML = isCollapsed
        ? '<svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" /></svg>'
        : '<svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" /></svg>';
}

/**
 * Category Collapse/Expand Toggle Handler with Animation Support
 * 
 * Handles category collapse/expand interactions with smooth CSS transitions
 * Updates both the visual state and saves the preference to the database
 * Uses class-based animations for better performance and reliability
 * 
 * @param {string} pageName - Name of the page containing the category
 * @param {string} categoryTitle - Title of the category to toggle
 */
function toggleCategory(pageName, categoryTitle) {
    // Find the category elements in the DOM
    const header = document.querySelector(`.card-window[data-category-title="${categoryTitle}"] h2`);
    if (!header) {
        console.error('Category header not found:', categoryTitle);
        return;
    }
    
    const card = header.closest('.card-window');
    const list = card.querySelector('.stash-list');
    
    // Determine current state by checking classes
    const isCurrentlyCollapsed = list.classList.contains('collapsed');
    const newState = isCurrentlyCollapsed ? 'open' : 'collapsed';
    
    // Apply smooth animated transition using classes
    if (isCurrentlyCollapsed) {
        // Expanding: remove collapsed class
        list.classList.remove('collapsed');
        list.classList.add('expanded');
        // Remove inline display style if it exists
        list.style.display = '';
    } else {
        // Collapsing: add collapsed class
        list.classList.add('collapsed');
        list.classList.remove('expanded');
        // Remove inline display style if it exists
        list.style.display = '';
    }
    
    // Update collapse icon
    updateCollapseIcon(header, !isCurrentlyCollapsed);
    
    // Persist state change to server for future page loads
    fetch('/api/v1/stash/category/toggle', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            page_key: pageName,
            category_title: categoryTitle,
            state: newState
        })
    }).catch(error => {
        console.error('Failed to save collapse state to DB:', error);
        // Note: Visual change remains even if server update fails for better UX
    });
}

/**
 * Category Collapse State Application with Animation Classes
 * 
 * Applies saved collapse states from server data to all categories on page load
 * Reads data attributes set by server rendering and applies visual states with classes
 * instead of inline styles for proper CSS animation support
 */
function applyCollapseStates() {
    document.querySelectorAll('.card-window').forEach(card => {
        const header = card.querySelector('h2');
        const isCollapsed = card.dataset.collapsed === '1'; // Server sets this attribute
        const list = card.querySelector('.stash-list');
        
        if (!list) return; // Safety check
        
        // Remove any inline display styles
        list.style.display = '';
        
        // Apply visual state based on server data using classes
        if (isCollapsed) {
            list.classList.add('collapsed');
            list.classList.remove('expanded');
        } else {
            list.classList.add('expanded');
            list.classList.remove('collapsed');
        }
        
        // Update collapse icon to match state
        updateCollapseIcon(header, isCollapsed);
    });
}


/**
 * Settings Dropdown Management
 * 
 * Manages the visibility state of the settings dropdown menu in the top navigation
 * Prevents event bubbling and sets up click-outside-to-close behavior when opened
 * 
 * @param {Event} event - The click event that triggered the dropdown toggle
 */
function toggleDropdown(event) {
    event.stopPropagation();                // Prevent event from bubbling to document
    const dropdown = document.getElementById('settings-dropdown');
    
    dropdown.classList.toggle('hidden');
    
    // Set up click-outside detection when dropdown opens
    if (!dropdown.classList.contains('hidden')) {
        // Use capture phase to handle clicks before other elements can process them
        document.addEventListener('click', closeDropdownHandler, true);
    } else {
        // Clean up listener when dropdown closes to prevent memory leaks
        document.removeEventListener('click', closeDropdownHandler, true);
    }
}

/**
 * Settings Dropdown Close Handler
 * 
 * Automatically closes the settings dropdown when clicking outside of it
 * Checks both the button and dropdown to prevent premature closing during interaction
 * 
 * @param {Event} event - The click event to check if it's outside the dropdown
 */
function closeDropdownHandler(event) {
    const dropdown = document.getElementById('settings-dropdown');
    const button = document.getElementById('settings-button');
    
    // Close dropdown only if click is outside both button and dropdown areas
    if (!button.contains(event.target) && !dropdown.contains(event.target)) {
        dropdown.classList.add('hidden');
        // Remove listener to prevent memory leaks
        document.removeEventListener('click', closeDropdownHandler, true);
    }
}

/**
 * Custom Delete Confirmation Modal Creation
 * 
 * Creates and displays a themed delete confirmation dialog with proper styling and
 * animation. Stores form reference globally for later submission processing
 * 
 * @param {string} stashName - Name of the stash to be deleted (for display)
 * @param {HTMLFormElement} form - The form element that will handle the deletion
 */
function showDeleteModal(stashName, form) {
    // Create custom modal HTML with proper styling and animations
    const modalHtml = `
        <div id="deleteConfirmModal" class="fixed inset-0 bg-black/75 backdrop-blur-sm flex items-center justify-center z-50 animate-in fade-in duration-300">
            <div class="bg-gray-800/95 backdrop-blur-md rounded-lg p-6 w-full max-w-sm shadow-2xl border border-red-700/50 animate-in zoom-in-95 slide-in-from-bottom-4 duration-300">
                <!-- Delete Warning Icon -->
                <div class="flex items-center justify-center w-16 h-16 mx-auto mb-4 bg-red-100 rounded-full">
                    <svg class="w-8 h-8 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                              d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
                    </svg>
                </div>
                
                <!-- Delete Confirmation Text -->
                <div class="text-center mb-6">
                    <h3 class="text-lg font-semibold text-white mb-2">Delete Stash?</h3>
                    <p class="text-gray-300 mb-2">Are you sure you want to delete <strong class="text-white">"${stashName}"</strong>?</p>
                    <p class="text-red-400 text-sm">This action cannot be undone.</p>
                </div>
                
                <!-- Action Buttons -->
                <div class="flex justify-end space-x-3">
                    <button type="button" onclick="closeDeleteModal()"
                            class="bg-gray-600 hover:bg-gray-700 text-white font-medium py-2 px-4 rounded-lg transition-colors duration-200">
                        Cancel
                    </button>
                    <button type="button" onclick="confirmDelete()"
                            class="bg-red-600 hover:bg-red-700 text-white font-medium py-2 px-4 rounded-lg transition-colors duration-200">
                        Delete Stash
                    </button>
                </div>
            </div>
        </div>
    `;
    
    // Insert modal into DOM
    document.body.insertAdjacentHTML('beforeend', modalHtml);
    
    // Store form reference globally for confirmation handler
    window.pendingDeleteForm = form;
}

/**
 * Delete Confirmation Modal Cleanup
 * 
 * Removes the delete confirmation modal from DOM and cleans up form reference
 * Ensures proper cleanup to prevent memory leaks and stale references
 */
function closeDeleteModal() {
    const modal = document.getElementById('deleteConfirmModal');
    if (modal) {
        modal.remove();
    }
    // Clear global form reference to prevent stale data
    window.pendingDeleteForm = null;
}

/**
 * Delete Action Confirmation Handler
 * 
 * Processes the actual delete action after user confirmation by temporarily
 * bypassing the form's custom submit handler and allowing normal submission
 */
function confirmDelete() {
  const formToSubmit = window.pendingDeleteForm;
  if (!formToSubmit) {
    console.error("No pending delete form found");
    return;
  }

  closeDeleteModal();

  // Mark form confirmed to bypass confirmation modal
  formToSubmit.setAttribute('data-confirmed', 'true');

  // Use native form submission to ensure cross-browser compatibility
  formToSubmit.submit();
}


/**
 * Delete Confirmation Interface Handler
 * 
 * Handles delete button clicks by finding the associated form and showing
 * the custom delete confirmation modal. This provides a more user-friendly
 * alternative to browser's default confirm() dialog
 * 
 * @param {string} stashName - Name of the stash to delete
 * @returns {boolean} Always returns false to prevent immediate form submission
 */
function confirmDeleteStash(stashName) {
    console.log('confirmDeleteStash called for:', stashName); // Debug log
    
    // Find the associated form element using consistent naming convention
    const form = document.getElementById(`deleteForm-${stashName}`);
    if (!form) {
        console.error(`Form deleteForm-${stashName} not found`);
        alert('Error: Could not find delete form');
        return false;
    }
    
    console.log('Form found, showing modal'); // Debug log
    showDeleteModal(stashName, form);
    return false; // Prevent any immediate form submission
}

/**
 * Application Initialization and Event Management
 * 
 * Main entry point that sets up the complete application interface based on
 * current page mode (dashboard view or index page). Configures event listeners
 * for all user interactions and handles both keyboard and mouse events
 */
document.addEventListener('DOMContentLoaded', function() {
    // Determine application mode based on URL parameters
    const urlParams = new URLSearchParams(window.location.search);
    const pageName = urlParams.get('n');
    
    if (pageName) {
        // Dashboard view mode: initialize advanced dashboard features
        initializeDashboard();
        initializePublicToggle();
    } else {
        // Index page mode: set up page creation and management features
        const pageNameInput = document.getElementById('page-name-input');
        if (pageNameInput) {
            // Enable Enter key submission for quick page creation
            pageNameInput.addEventListener('keypress', function(event) {
                if (event.key === 'Enter') {
                    goToPage();
                }
            });
        }
        
        // Global click handler to close stash menus when clicking outside
        document.addEventListener('click', function(event) {
            // Check if click is outside any stash menu trigger
            if (!event.target.closest('[onclick*="toggleStashMenu"]')) {
                // Close all open stash menus for clean UI state
                document.querySelectorAll('[id^="menu-"]').forEach(menu => {
                    menu.classList.add('hidden');
                });
            }
        });
        
        // Global keyboard shortcut handler for modal management
        document.addEventListener('keydown', function(e) {
            if (e.key === 'Escape') {
                // Escape key closes all modal dialogs
                closeRenameModal();
                closeCloneModal();
                closeImportModal();
                closeDeleteModal();
            }
        });
    }

    /**
     * Delete Form Submission Interception
     * 
     * Intercepts delete form submissions to show custom confirmation dialog
     * instead of browser's default confirm(). Allows confirmed deletions to proceed
     */
    document.addEventListener('submit', function(event) {
    if (event.target.action && event.target.action.includes('stash/delete')) {
        // Allow native submissions after confirmation by checking the flag
        if (event.target.getAttribute('data-confirmed') === 'true') {
        event.target.removeAttribute('data-confirmed'); // clean flag
        return true; // Let submission proceed
        }

        event.preventDefault();
        const pageKeyInput = event.target.querySelector('input[name=page_key]');
        const pageKey = pageKeyInput ? pageKeyInput.value : '';
        showDeleteModal(pageKey, event.target);
        return false;
    }
    });

    
    /**
     * Dropdown Menu Click Event Management
     * 
     * Handles clicks within dropdown menus to prevent unwanted menu closure
     * while still allowing form submissions and other interactive elements
     */
    document.addEventListener('click', function(event) {
        const isInDropdown = event.target.closest('[id^="menu-"]');
        const isDeleteForm = event.target.closest('form[action*="/stash/delete"]');
        const isSubmitButton = event.target.closest('button[type="submit"]');
        
        // Stop event propagation for dropdown interactions (except delete forms and submit buttons)
        if (isInDropdown && !isDeleteForm && !isSubmitButton) {
            event.stopPropagation();
        }
    });
});

/**
 * Keyboard Shortcut Handler for Dashboard
 * 
 * Processes keyboard shortcuts for quick actions in view mode:
 * - Ctrl/Cmd + E: Switch to edit mode for current stash
 * 
 * @param {KeyboardEvent} e - Keyboard event object
 */
function handleDashboardKeyboard(e) {
    // Enter edit mode with Ctrl/Cmd + E
    if ((e.ctrlKey || e.metaKey) && e.key === 'e') {
        e.preventDefault();
        
        // Only trigger if not typing in an input field
        if (isInputFocused()) {
            return;
        }
        
        // Get current stash name from URL parameter
        const urlParams = new URLSearchParams(window.location.search);
        const stashName = urlParams.get('n');
        
        if (stashName) {
            // Navigate to edit mode
            window.location.href = `/edit?n=${encodeURIComponent(stashName)}`;
        }
    }
}

/**
 * Check if an input element is currently focused
 * 
 * Prevents keyboard shortcuts from triggering when user is typing in a text field.
 * 
 * @returns {boolean} True if an input/textarea is focused
 */
function isInputFocused() {
    const activeElement = document.activeElement;
    return activeElement && (
        activeElement.tagName === 'INPUT' ||
        activeElement.tagName === 'TEXTAREA' ||
        activeElement.isContentEditable
    );
}

// Initialize keyboard shortcuts when page loads
document.addEventListener('keydown', handleDashboardKeyboard);

// Initialize dashboard keyboard shortcuts
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() {
        document.addEventListener('keydown', handleDashboardKeyboard);
    });
} else {
    document.addEventListener('keydown', handleDashboardKeyboard);
}

/**
 * Clipboard Copy with Browser Compatibility
 * 
 * Attempts to copy text to the user's clipboard using the modern Clipboard API
 * with automatic fallback to document.execCommand for older browsers or non-secure
 * contexts (HTTP). The modern API requires HTTPS or localhost for security.
 * 
 * @param {string} text - The text content to copy to clipboard
 * @returns {Promise<boolean>} Resolves to true if copy succeeded, false otherwise
 */
async function copyToClipboard(text) {
    // Try modern Clipboard API first (requires HTTPS or localhost)
    if (navigator.clipboard && window.isSecureContext) {
        try {
            await navigator.clipboard.writeText(text);
            return true;
        } catch (err) {
            console.error('Clipboard API failed:', err);
        }
    }
    
    // Fallback for older browsers or non-secure contexts
    try {
        // Create temporary textarea for copy operation
        const textArea = document.createElement('textarea');
        textArea.value = text;
        textArea.style.position = 'fixed';
        textArea.style.left = '-999999px';
        textArea.style.top = '-999999px';
        document.body.appendChild(textArea);
        textArea.focus();
        textArea.select();
        
        // Execute legacy copy command
        const successful = document.execCommand('copy');
        document.body.removeChild(textArea);
        return successful;
    } catch (err) {
        console.error('Fallback copy failed:', err);
        return false;
    }
}

/**
 * Toast Notification Display System
 * 
 * Creates and displays a temporary notification toast with smooth animations
 * Automatically removes previous notifications to prevent stacking and cleans
 * up after 3 seconds with fade-out animation
 * 
 * @param {string} message - The notification message to display to the user
 * @param {string} type - Notification type: 'success' (green) or 'error' (red)
 */
function showNotification(message, type = 'success') {
    // Remove any existing notifications to prevent stacking
    const existing = document.getElementById('clipboard-notification');
    if (existing) {
        existing.remove();
    }
    
    // Create notification element with appropriate styling classes
    const notification = document.createElement('div');
    notification.id = 'clipboard-notification';
    notification.className = `clipboard-notification clipboard-notification-${type}`;
    notification.textContent = message;
    
    // Add to DOM for rendering
    document.body.appendChild(notification);
    
    // Trigger animation after brief delay for CSS transition
    setTimeout(() => notification.classList.add('show'), 10);
    
    // Auto-dismiss after 3 seconds with fade-out animation
    setTimeout(() => {
        notification.classList.remove('show');
        setTimeout(() => notification.remove(), 300);
    }, 3000);
}

/**
 * Public/Private Toggle Button Functionality
 * 
 * Handles the interactive behavior of the public/private toggle button that allows
 * stash owners to control visibility of their stash pages. Manages button state,
 * icon changes, and API communication with the server to persist visibility settings.
 */

/**
 * Toggle Button Initialization System
 * 
 * Sets up the public toggle button with current state from server data and
 * attaches click event handler for state changes. Reads initial visibility
 * state from data attributes set during server rendering.
 */
function initializePublicToggle() {
    const toggleBtn = document.getElementById('toggle-public-btn');
    if (!toggleBtn) return;                  // Exit if button doesn't exist on page
    
    const pageKey = toggleBtn.dataset.pageKey;
    const isPublic = toggleBtn.dataset.isPublic;
    
    // Set initial button state based on server data
    updateToggleButtonState(toggleBtn, isPublic === '1');
    
    // Attach click handler for toggle functionality
    toggleBtn.addEventListener('click', function() {
        togglePublicState(pageKey, toggleBtn);
    });
}

/**
 * Public State Toggle Handler with Clipboard Integration
 * 
 * Handles button clicks by sending API request to server and updating button
 * state on success. When toggling to public state, automatically copies the
 * public URL to clipboard and shows success notification. Provides user feedback
 * for both success and error cases to ensure users understand their action.
 * 
 * @param {string} pageKey - The unique identifier of the stash page
 * @param {HTMLElement} toggleBtn - The toggle button element to update
 */
function togglePublicState(pageKey, toggleBtn) {
    const currentState = toggleBtn.dataset.isPublic === '1';
    const newState = !currentState;          // Flip the current state
    
    // Disable button during API call to prevent double-clicks
    toggleBtn.disabled = true;
    toggleBtn.style.opacity = '0.6';
    
    // Send toggle request to server
    fetch('/api/v1/stash/toggle-public', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            page_key: pageKey,
            is_public: newState ? 1 : 0
        })
    })
    .then(response => {
        if (!response.ok) {
            throw new Error('Failed to toggle public state');
        }
        return response.json();
    })
    .then(async data => {
        // Update button state on successful API response
        toggleBtn.dataset.isPublic = newState ? '1' : '0';
        updateToggleButtonState(toggleBtn, newState);
        
        // Handle clipboard copy when toggling to public
        if (newState) {
            // Get username from data attribute (set by server)
            const username = toggleBtn.dataset.username;
            
            // Build public URL with correct format: /stash?n=pageName&u=username
            const publicUrl = `${window.location.origin}/stash?n=${encodeURIComponent(pageKey)}&u=${encodeURIComponent(username)}`;
            
            // Attempt to copy URL to clipboard
            const copied = await copyToClipboard(publicUrl);
            
            if (copied) {
                showNotification('✓ Public URL copied to clipboard!', 'success');
            } else {
                showNotification('⚠ Stash is now public, but clipboard copy failed', 'error');
            }
        } else {
            // Toggled to private
            showNotification('✓ Stash is now private', 'success');
        }
        
        console.log('Public state toggled:', newState ? 'Public' : 'Private');
    })
    .catch(error => {
        console.error('Error toggling public state:', error);
        showNotification('Network error - please try again', 'error');
    })
    .finally(() => {
        // Re-enable button after API call completes
        toggleBtn.disabled = false;
        toggleBtn.style.opacity = '1';
    });
}

/**
 * Toggle Button Visual State Manager
 * 
 * Updates all visual aspects of the toggle button to match the current state
 * including icon, text label, and CSS classes for color scheme. Ensures
 * consistent visual feedback across all button elements.
 * 
 * @param {HTMLElement} toggleBtn - The toggle button element to update
 * @param {boolean} isPublic - Whether the stash is currently public
 */
function updateToggleButtonState(toggleBtn, isPublic) {
    const text = toggleBtn.querySelector('.toggle-text');
    const privateIcon = toggleBtn.querySelector('.icon-private');
    const publicIcon = toggleBtn.querySelector('.icon-public');
    
    if (!text || !privateIcon || !publicIcon) {
        console.error('Toggle button elements not found');
        return;
    }
    
    if (isPublic) {
        // Public state: show unlock icon, hide lock icon
        publicIcon.style.display = 'block';
        privateIcon.style.display = 'none';
        text.textContent = 'Public';
        toggleBtn.dataset.isPublic = '1';
    } else {
        // Private state: show lock icon, hide unlock icon
        privateIcon.style.display = 'block';
        publicIcon.style.display = 'none';
        text.textContent = 'Private';
        toggleBtn.dataset.isPublic = '0';
    }
}

/**
 * Global Function Exposure
 * 
 * Makes functions available on the global window object for use by inline event
 * handlers in HTML templates. This ensures compatibility with server-rendered HTML
 * that references these functions directly in onclick attributes and other inline handlers
 */
window.toggleDropdown = toggleDropdown;
window.goToPage = goToPage;
window.toggleStashMenu = toggleStashMenu;
window.openRenameModal = openRenameModal;
window.closeRenameModal = closeRenameModal;
window.openCloneModal = openCloneModal;
window.closeCloneModal = closeCloneModal;
window.openImportModal = openImportModal;
window.closeImportModal = closeImportModal;
window.showDeleteModal = showDeleteModal;
window.closeDeleteModal = closeDeleteModal;
window.confirmDelete = confirmDelete;
window.confirmDeleteStash = confirmDeleteStash;
window.toggleCategory = toggleCategory;
window.initializePublicToggle = initializePublicToggle;
window.togglePublicState = togglePublicState;
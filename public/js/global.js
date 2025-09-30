// /js/global.js

/**
 * Global Application Utilities Module
 * 
 * This module provides universal functionality shared across all pages of the Stash
 * application. It handles core UI interactions and navigation that need to work
 * consistently throughout the application including:
 * - Settings dropdown menu management with click-outside behavior
 * - Page creation and navigation with input validation
 * - Stash context menu management with exclusive visibility
 * - Modal dialog system for rename, clone, and import operations
 * - Dashboard viewport centering for optimal user experience
 * - Global keyboard shortcuts and accessibility features
 * 
 * Dependencies:
 * - None (standalone utility functions)
 * 
 * Usage:
 * This file is loaded on every page and exposes functions globally for use
 * by inline event handlers and external scripts
 */

/**
 * Responsive Behavior Configuration
 * 
 * These constants control timing, thresholds, and positioning for responsive
 * dashboard behavior across different device types and screen sizes
 */
let resizeTimer;                            // Debounce timer for window resize events
const TOPBAR_HEIGHT = 50;                  // Height of navigation bar for viewport calculations
const MOBILE_BREAKPOINT = 768;             // Pixel threshold for mobile vs desktop behavior
const DASHBOARD_CENTER_X = 2000;           // Horizontal center point of dashboard canvas
const DASHBOARD_CENTER_Y = 1250;           // Vertical center point of dashboard canvas
const RESIZE_DEBOUNCE_DELAY = 150;         // Milliseconds to wait before processing resize
const FOCUS_CENTER_DELAY = 100;            // Delay before centering when window regains focus
const INITIAL_CENTER_DELAY = 100;          // Delay for initial dashboard centering

/**
 * Input Validation Configuration
 * 
 * Regular expression and rules for validating user input in page names
 * These restrictions ensure URL safety and file system compatibility
 */
const PAGE_NAME_PATTERN = /^[\w.-]+$/;      // Only letters, numbers, underscores, dashes, dots

/**
 * Settings Dropdown Management
 * 
 * Handles the main settings dropdown menu with proper click-outside behavior
 * Uses event capture to ensure clicks are processed before other handlers
 * 
 * @param {Event} event - The click event from the settings button
 */
function toggleDropdown(event) {
    event.stopPropagation();                // Prevent event from bubbling to document
    const dropdown = document.getElementById('settings-dropdown');
    
    // Toggle visibility state
    dropdown.classList.toggle('hidden');
    
    // Set up click-outside detection when dropdown opens
    if (!dropdown.classList.contains('hidden')) {
        // Use capture phase to handle clicks before other elements can process them
        document.addEventListener('click', closeDropdownHandler, true);
    } else {
        // Clean up listener when dropdown closes
        document.removeEventListener('click', closeDropdownHandler, true);
    }
}

/**
 * Click-Outside Handler for Settings Dropdown
 * 
 * Closes the settings dropdown when user clicks outside of it
 * Checks both the button and dropdown to prevent premature closing
 * 
 * @param {Event} event - The document click event to evaluate
 */
function closeDropdownHandler(event) {
    const dropdown = document.getElementById('settings-dropdown');
    const button = document.getElementById('settings-button');
    
    // Close dropdown only if click is outside both button and dropdown
    if (!button.contains(event.target) && !dropdown.contains(event.target)) {
        dropdown.classList.add('hidden');
        // Remove listener to prevent memory leaks
        document.removeEventListener('click', closeDropdownHandler, true);
    }
}

/**
 * Page Navigation and Creation System
 * 
 * Validates user input for new page names and navigates to the stash page
 * Implements security restrictions to prevent invalid URLs and file names
 * Provides immediate feedback for validation errors
 */
function goToPage() {
    console.log('goToPage() called'); // DEBUG
    
    const pageNameInput = document.getElementById('page-name-input');
    if (!pageNameInput) {
        alert('Input field not found!');
        return;
    }
    
    // Extract and sanitize user input
    let pageName = pageNameInput.value.trim();
    console.log('Page name:', pageName); // DEBUG
    
    // Validate that user provided a name
    if (!pageName) {
        alert('Please enter a page name.');
        return;
    }
    
    // Security validation: restrict to safe characters for URLs and file systems
    if (!pageName.match(PAGE_NAME_PATTERN)) {
        alert('Invalid page name. Use only letters, numbers, underscores, and dashes.');
        return;
    }
    
    // Build URL with proper encoding to prevent injection attacks
    let url = '/stash?n=' + encodeURIComponent(pageName);
    console.log('Navigating to:', url); // DEBUG
    window.location.href = url;
}

/**
 * Stash Context Menu Management
 * 
 * Manages dropdown menus for individual stash items with exclusive visibility
 * Ensures only one menu is open at a time for better user experience
 * 
 * @param {string} stashName - Identifier for the stash whose menu to toggle
 */
function toggleStashMenu(stashName) {
    console.log('toggleStashMenu:', stashName); // DEBUG
    
    // Close all other menus to maintain exclusive visibility
    document.querySelectorAll('[id^="menu-"]').forEach(menu => {
        if (menu.id !== `menu-${stashName}`) {
            menu.classList.add('hidden');
        }
    });
    
    // Toggle the requested menu
    const menu = document.getElementById(`menu-${stashName}`);
    if (menu) {
        menu.classList.toggle('hidden');
    }
}

/**
 * Rename Modal Management
 * 
 * Opens the rename dialog with the current page name pre-filled
 * Focuses and selects text for immediate editing convenience
 * 
 * @param {string} pageName - Current name of the page to rename
 */
function openRenameModal(pageName) {
    console.log('openRenameModal:', pageName); // DEBUG
    
    // Pre-populate form fields with current values
    document.getElementById('old_page_name').value = pageName;
    document.getElementById('new_page_name').value = pageName;
    
    // Show modal and focus input for immediate editing
    document.getElementById('renameModal').classList.remove('hidden');
    document.getElementById('new_page_name').focus();
    document.getElementById('new_page_name').select(); // Select all text for easy replacement
}

/**
 * Rename Modal Closure
 * 
 * Closes the rename modal and cleans up any temporary state
 */
function closeRenameModal() {
    document.getElementById('renameModal').classList.add('hidden');
}

/**
 * Clone Modal Management
 * 
 * Opens the clone dialog with source page information and suggested clone name
 * Automatically generates a suitable default name with "-copy" suffix
 * 
 * @param {string} pageName - Name of the page to clone
 */
function openCloneModal(pageName) {
    console.log('openCloneModal:', pageName); // DEBUG
    
    // Set up source page information
    document.getElementById('source_page_name').value = pageName;
    document.getElementById('source_page_display').textContent = pageName;
    
    // Generate suggested clone name with standard suffix
    document.getElementById('clone_new_page_name').value = `${pageName}-copy`;
    
    // Show modal and focus input for editing
    document.getElementById('cloneModal').classList.remove('hidden');
    document.getElementById('clone_new_page_name').focus();
    document.getElementById('clone_new_page_name').select(); // Select for easy modification
}

/**
 * Clone Modal Closure
 * 
 * Closes the clone modal and resets any temporary state
 */
function closeCloneModal() {
    document.getElementById('cloneModal').classList.add('hidden');
}

/**
 * Import Modal Management
 * 
 * Opens the import dialog for uploading dashboard data from external sources
 */
function openImportModal() {
    document.getElementById('importModal').classList.remove('hidden');
}

/**
 * Import Modal Closure
 * 
 * Closes the import modal and cleans up any file upload state
 */
function closeImportModal() {
    document.getElementById('importModal').classList.add('hidden');
}

/**
 * Dashboard Viewport Centering System
 * 
 * Centers the dashboard viewport on the main content area for optimal viewing
 * Calculates scroll position based on content center and viewport dimensions
 * Only used on desktop devices where the full canvas is navigable
 */
function centerDashboardView() {
    const wrapper = document.getElementById('dashboard-wrapper');
    if (!wrapper) return;
    
    // Calculate scroll position to center content in current viewport
    const targetScrollLeft = DASHBOARD_CENTER_X - (window.innerWidth / 2);
    const targetScrollTop = DASHBOARD_CENTER_Y - (window.innerHeight / 2);
    
    // Apply scroll position with bounds checking to prevent negative values
    wrapper.scrollLeft = Math.max(0, targetScrollLeft);
    wrapper.scrollTop = Math.max(0, targetScrollTop);
}

/**
 * Dashboard Initialization for Edit Views
 * 
 * Sets up responsive dashboard behavior including viewport centering and
 * resize handling. Only activates on desktop devices where full canvas
 * navigation provides value to the user experience
 */
function initializeDashboard() {
    // Only enable advanced dashboard features on desktop devices
    if (window.innerWidth > MOBILE_BREAKPOINT) {
        // Initial centering with delay to ensure DOM is fully rendered
        setTimeout(centerDashboardView, INITIAL_CENTER_DELAY);
        
        // Debounced resize handler to maintain centered view during window resizing
        window.addEventListener('resize', () => {
            clearTimeout(resizeTimer);
            resizeTimer = setTimeout(centerDashboardView, RESIZE_DEBOUNCE_DELAY);
        });
        
        // Re-center when window regains focus (handles tab switching)
        window.addEventListener('focus', () => {
            setTimeout(centerDashboardView, FOCUS_CENTER_DELAY);
        });
    }
}

/**
 * Global Application Initialization
 * 
 * Sets up universal functionality when the DOM is ready including:
 * - Page-specific initialization based on URL parameters
 * - Global event listeners for keyboard shortcuts and click handling
 * - Input field enhancements for better user experience
 */
document.addEventListener('DOMContentLoaded', function() {
    console.log('Global JS initialized'); // DEBUG
    
    // Determine application mode based on URL parameters
    const urlParams = new URLSearchParams(window.location.search);
    const pageName = urlParams.get('n');
    
    if (pageName) {
        // Dashboard view mode: initialize advanced dashboard features
        initializeDashboard();
    } else {
        // Index page mode: enhance page creation input
        const pageNameInput = document.getElementById('page-name-input');
        if (pageNameInput) {
            // Enable Enter key submission for quick page creation
            pageNameInput.addEventListener('keypress', function(event) {
                if (event.key === 'Enter') {
                    goToPage();
                }
            });
        }
    }
    
    // Global click handler to close stash menus when clicking outside
    document.addEventListener('click', function(event) {
        // Check if click is outside any stash menu trigger
        if (!event.target.closest('[onclick*="toggleStashMenu"]')) {
            // Close all open stash menus
            document.querySelectorAll('[id^="menu-"]').forEach(menu => {
                menu.classList.add('hidden');
            });
        }
    });
    
    // Global keyboard shortcut handler
    document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape') {
            // Escape key closes all modal dialogs
            closeRenameModal();
            closeCloneModal();
            closeImportModal();
        }
    });
});

/**
 * Global Function Exposure
 * 
 * Makes functions available on the window object for use by inline event handlers
 * This is necessary for legacy compatibility and simplified HTML event handling
 * Modern modules can import functions directly, but global exposure supports
 * server-rendered HTML with inline onclick attributes
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

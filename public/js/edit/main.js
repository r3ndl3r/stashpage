// /js/edit/main.js

/**
 * Dashboard Main Controller Module
 * 
 * This is the primary entry point for the stash dashboard editor. It coordinates all
 * functionality between modules and manages the overall application state including:
 * - Dashboard initialization and data synchronization
 * - Event delegation for all user interactions
 * - Viewport management and responsive behavior
 * - Form submission and data persistence
 * - Keyboard shortcuts and accessibility features
 * 
 * Dependencies:
 * - draggable.js: For drag-and-drop functionality on cards and items
 * - modal.js: For all modal dialogs and user confirmations
 * - actions.js: For CRUD operations on categories and stash items
 * 
 * Global Variables:
 * - dashboardData: Master array containing all category and stash item data
 * - resizeTimer: Debounce timer for responsive viewport adjustments
 * 
 */

import { makeDraggable, makeSortable } from './draggable.js';
import { 
    showEditCategoryModal,
    showAddCategoryModal, 
    showAddStashModal, 
    showEditStashModal, 
    closeModal, 
    handleConfirm, 
    showAlert, 
    showConfirm 
} from './modal.js';
import { 
    deleteCategory, 
    deleteStash, 
    editCategory,
    addCategory, 
    addStash, 
    editStash,
    resetPositions 
} from './actions.js';

/**
 * Application State Management
 * 
 * Central data store that maintains the current state of all dashboard elements
 * This array is synchronized with the DOM and used for form submission
 */
let dashboardData = [];

/**
 * Responsive Behavior Configuration
 * 
 * Controls timing and thresholds for responsive dashboard behavior
 * These values affect viewport centering and mobile experience
 */
let resizeTimer; 
const TOPBAR_HEIGHT = 50;                  // Height of the top navigation bar in pixels
const MOBILE_BREAKPOINT = 768;             // Pixel width threshold for mobile vs desktop behavior
const VIEWPORT_CENTER_DELAY = 50;          // Milliseconds to wait before initial centering
const RESIZE_DEBOUNCE_DELAY = 100;         // Milliseconds to debounce window resize events

/**
 * Global Function Exposure
 * 
 * Exposes modal and save functions to the global window object for access from
 * inline event handlers and external scripts (required for some legacy integrations)
 */
window.closeModal = closeModal;
window.handleConfirm = handleConfirm;
window.showAlert = showAlert;
window.showConfirm = showConfirm;

/**
 * Dashboard Save Handler
 * 
 * Synchronizes current dashboard state with the hidden form field and submits
 * the form to persist changes to the server. This function is exposed globally
 * to allow calling from save buttons and keyboard shortcuts
 */
window.saveDashboard = function() {
    const form = document.getElementById('stashForm');
    if (!form) return;
    
    // Update the hidden form field with current dashboard state
    syncDataForSubmission();
    
    // Submit the form to save changes to server
    form.submit(); 
}

/**
 * Viewport Centering System
 * 
 * Centers the dashboard viewport on the main content area to provide an optimal
 * initial view for users. Calculates scroll position based on content center point
 * and current viewport dimensions while accounting for the top navigation bar
 */
function centerDashboardView() {
    const wrapper = document.getElementById('dashboard-wrapper');

    if (wrapper) {
        // These coordinates represent the center of the large dashboard canvas
        const contentCenterX = 2000;               // Horizontal center of canvas content
        const contentCenterY = 1250;               // Vertical center of canvas content

        // Get current viewport dimensions for centering calculations
        const viewportWidth = window.innerWidth;
        const viewportHeight = window.innerHeight;

        // Calculate scroll position to center content in viewport
        const scrollX = contentCenterX - (viewportWidth / 2);
        
        // Adjust vertical centering to account for top navigation bar
        const scrollY = contentCenterY - (viewportHeight / 2) + (TOPBAR_HEIGHT / 2);
        
        // Apply calculated scroll position
        wrapper.scrollLeft = scrollX;
        wrapper.scrollTop = scrollY;
    }
}

/**
 * Data Synchronization System
 * 
 * Extracts current dashboard state from DOM elements and synchronizes it with
 * the dashboardData array and hidden form field. This ensures that all changes
 * made through the UI are captured for server submission
 */
function syncDataForSubmission() {
    const categoryElements = document.querySelectorAll('#dashboard-canvas .card-window');
    const newDashboardData = [];
    
    // Process each category card to extract current state
    categoryElements.forEach(card => {
        const title = card.dataset.categoryTitle;
        
        // Find existing category data or create new structure
        let category = dashboardData.find(c => c.title === title);
        
        if (!category) {
            // Create new category structure for newly added cards
             category = {
                title: card.dataset.categoryTitle,
                icon: card.dataset.categoryIcon || '',
                baseUrl: card.dataset.categoryBaseUrl || '',
                collapsed: 0,                       // Default to expanded state
                items: []
            };
        }

        // Update category position from current DOM element position
        category.x = parseInt(card.style.left, 10) || 0;
        category.y = parseInt(card.style.top, 10) || 0;
        category.icon = card.dataset.categoryIcon || '';
        category.baseUrl = card.dataset.categoryBaseUrl || '';

        // Rebuild items array from current DOM order (reflects user sorting)
        category.items = [];
        card.querySelectorAll('.stash-tile').forEach(tile => {
            category.items.push({
                name: tile.dataset.name,
                url: tile.dataset.url,
                icon: tile.dataset.icon
            });
        });
        
        newDashboardData.push(category);
    });
    
    // Update the master data array
    dashboardData = newDashboardData;

    // Serialize data for form submission
    const dataField = document.getElementById('stash_data');
    if (dataField) {
        dataField.value = JSON.stringify(dashboardData, null, 2);
    }
}

/**
 * Central Event Handler for Dashboard Interactions
 * 
 * Uses event delegation to handle all button clicks within the dashboard canvas
 * This approach is more efficient than individual event listeners and automatically
 * handles dynamically added elements without requiring re-binding
 * 
 * @param {Event} event - The click event from the dashboard canvas
 */
function handleCanvasClick(event) {
    
    // Only process clicks on buttons with action data attributes
    const button = event.target.closest('button');
    if (!button || !button.dataset.action) return;

    const action = button.dataset.action;
    const element = button.closest('.stash-tile') || button.closest('.card-window');

    // Route actions to appropriate handlers based on button's data-action attribute
    switch (action) {
        case 'add-stash':
            // Show modal to add new stash item to clicked category
            if (element && element.classList.contains('card-window')) {
                showAddStashModal(element, addStash); 
            }
            break;
        case 'edit-category':
            // Show modal to edit category properties with conflict checking
            if (element && element.classList.contains('card-window')) {
                showEditCategoryModal(element, () => editCategory(element, dashboardData));
            }
            break;
        case 'edit-stash': 
            // Show modal to edit individual stash item properties
            if (element && element.classList.contains('stash-tile')) {
                showEditStashModal(element, editStash);
            }
            break;
        case 'delete-category':
            // Confirm deletion before removing entire category and all its items
            showConfirm('Delete this entire category? This cannot be undone.', confirmed => {
                if (confirmed) deleteCategory(button);
            });
            break;
        case 'delete-stash':
            // Confirm deletion before removing individual stash item
            showConfirm('Delete this stash link?', confirmed => {
                if (confirmed) deleteStash(button);
            });
            break;
    }
}

/**
 * Dashboard Initialization System
 * 
 * Bootstraps the entire dashboard application by:
 * - Building initial data structure from server-rendered DOM
 * - Enabling drag-and-drop functionality on all elements
 * - Setting up event listeners for user interactions
 * - Configuring responsive behavior based on device type
 * - Implementing keyboard shortcuts for power users
 */
function init() {
    
    // Build initial dashboardData array from server-rendered DOM elements
    document.querySelectorAll('#dashboard-canvas .card-window').forEach(card => {
        const category = {
            title: card.dataset.categoryTitle,
            icon: card.dataset.categoryIcon || '',
            baseUrl: card.dataset.categoryBaseUrl || '',
            x: parseInt(card.style.left, 10) || 0,
            y: parseInt(card.style.top, 10) || 0,
            items: []
        };
        
        // Extract stash items from DOM and add to category data
        card.querySelectorAll('.stash-tile').forEach(tile => {
            category.items.push({
                name: tile.dataset.name,
                url: tile.dataset.url,
                icon: tile.dataset.icon
            });
        });
        dashboardData.push(category);
        
        // Enable drag-and-drop functionality for category cards and stash lists
        makeDraggable(card);
        makeSortable(card.querySelector('.stash-list'));
    });

    
    // Set up event delegation for all dashboard interactions
    const canvas = document.getElementById('dashboard-canvas');
    if (canvas) {
        canvas.addEventListener('click', handleCanvasClick);
    }
    
    // Attach handlers to main action buttons in the interface
    document.getElementById('add-category-btn')?.addEventListener('click', () => {
        showAddCategoryModal(addCategory);
    });
    
    document.getElementById('reset-positions-btn')?.addEventListener('click', () => {
        showConfirm('Are you sure you want to reset all category positions? This action is not saved until you click the Save Dashboard button.', (confirmed) => {
            if (confirmed) {
                resetPositions();
            }
        });
    });
    
    // Enable Ctrl+S / Cmd+S keyboard shortcut for quick saving
    document.addEventListener('keydown', function(e) {
        if ((e.ctrlKey || e.metaKey) && e.key === 's') {
            e.preventDefault();                     // Prevent browser's default save dialog
            window.saveDashboard(); 
        }
    });

    // Configure responsive behavior based on device capabilities
    if (window.innerWidth > MOBILE_BREAKPOINT) {
        // Desktop: Center the view on content and respond to window resizing
        setTimeout(centerDashboardView, VIEWPORT_CENTER_DELAY); 

        // Debounced resize handler to maintain centered view during window resizing
        window.addEventListener('resize', () => {
            clearTimeout(resizeTimer);
            resizeTimer = setTimeout(centerDashboardView, RESIZE_DEBOUNCE_DELAY);
        });
    } else {
        // Mobile: Start at top of dashboard for optimal mobile navigation
        const wrapper = document.getElementById('dashboard-wrapper');
        if (wrapper) {
            wrapper.scrollTop = 0;
        }
    }
}

/**
 * Keyboard Shortcut Handler for Edit Mode
 * 
 * Processes keyboard shortcuts in edit mode:
 * - Ctrl/Cmd + E: Return to view mode
 * 
 * @param {KeyboardEvent} e - Keyboard event object
 */
function handleEditModeKeyboard(e) {
    // Return to view mode with Ctrl/Cmd + E
    if ((e.ctrlKey || e.metaKey) && e.key === 'e') {
        e.preventDefault();
        
        const urlParams = new URLSearchParams(window.location.search);
        const stashName = urlParams.get('n');
        
        if (stashName) {
            window.location.href = `/stash?n=${encodeURIComponent(stashName)}`;
        }
    }
}

// Initialize in edit mode
document.addEventListener('keydown', handleEditModeKeyboard);


/**
 * Application Entry Point
 * 
 * Initializes the dashboard once the DOM is fully loaded
 * This ensures all server-rendered elements are available for processing
 */
document.addEventListener('DOMContentLoaded', init);

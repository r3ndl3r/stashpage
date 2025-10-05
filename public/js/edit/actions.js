// /js/edit/actions.js

/**
 * Dashboard Actions Module
 * 
 * This module handles all user actions for the stash dashboard editor including:
 * - Creating, editing, and deleting categories
 * - Creating, editing, and deleting stash items (bookmarks)
 * - URL validation and resolution
 * - Form input validation and sanitization
 * - DOM element creation and manipulation
 * 
 * Dependencies:
 * - modal.js: For showing alerts and closing modals
 * - draggable.js: For making new elements draggable and sortable
 */

import { showAlert, closeModal, getCategoryColor } from './modal.js';
import { makeDraggable, makeSortable } from './draggable.js';


/**
 * Configuration Constants
 * These values control validation limits, positioning, and security policies
 * Modify these values to adjust behavior without changing code logic
 */
const CONFIG = {
    CANVAS: {
        CENTER_X: 2000,                 // Horizontal center of the large canvas
        CENTER_Y: 1250,                 // Vertical center of the large canvas
        DEFAULT_OFFSET: 50              // Pixels to offset new items from exact center
    },
    VALIDATION: {
        MAX_TITLE_LENGTH: 100,          // Maximum characters for category/item titles
        MAX_URL_LENGTH: 2000,           // Maximum characters for URLs
        MAX_ICON_URL_LENGTH: 500        // Maximum characters for icon URLs
    },
    // Security policy: only these URL protocols are permitted
    ALLOWED_PROTOCOLS: ['http:', 'https:', 'ftp:', 'ftps:']
};


/**
 * URL Resolution and Validation
 * 
 * Resolves relative URLs against base URLs and validates all URLs for security
 * This function handles both absolute URLs and relative paths within a category's base URL
 * 
 * @param {string} url - The URL to resolve (may be relative or absolute)
 * @param {string} baseUrl - Base URL for resolving relative paths
 * @returns {string} The fully resolved and validated URL
 * @throws {Error} If the URL is invalid or uses a disallowed protocol
 */
function resolveUrl(url, baseUrl) {
    if (!url) return '';
    
    url = url.trim();
    baseUrl = (baseUrl || '').trim();
    
    // Check if URL is already absolute (has protocol)
    if (url.match(/^(https?:\/\/|ftps?:\/\/|\/\/)/i)) {
        return validateUrl(url);
    }
    
    // Handle relative URLs when base URL is provided
    if (baseUrl) {
        try {
            const base = new URL(baseUrl);
            const resolved = new URL(url, base);
            return validateUrl(resolved.toString());
        } catch (error) {
            throw new Error(`Invalid base URL or relative path: ${error.message}`);
        }
    }

    // If no base URL provided and URL isn't absolute, assume HTTPS
    if (!url.startsWith('//')) {
        url = 'https://' + url;
    }
    
    return validateUrl(url);
}


/**
 * URL Security Validation
 * 
 * Validates URLs to ensure they use allowed protocols
 * 
 * @param {string} url - The URL to validate
 * @returns {string} The validated URL
 * @throws {Error} If URL is invalid or poses security risk
 */
function validateUrl(url) {
    try {
        const urlObj = new URL(url);
        
        // Verify protocol is in allowed list
        if (!CONFIG.ALLOWED_PROTOCOLS.includes(urlObj.protocol)) {
            throw new Error(`Protocol ${urlObj.protocol} is not allowed`);
        }
        
        // Internal network restriction removed - all hostnames allowed
        
        return urlObj.toString();
    } catch (error) {
        throw new Error(`Invalid URL: ${error.message}`);
    }
}


/**
 * Text Input Validation
 * 
 * Validates and sanitizes text inputs with length limits and requirement checks
 * Provides consistent validation across all form inputs
 * 
 * @param {string} text - Text to validate
 * @param {string} fieldName - Human-readable field name for error messages
 * @param {number} maxLength - Maximum allowed character count
 * @param {boolean} required - Whether the field must have content
 * @returns {string} Validated and trimmed text
 * @throws {Error} If validation fails
 */
function validateText(text, fieldName, maxLength, required = true) {
    if (typeof text !== 'string') {
        throw new Error(`${fieldName} must be a string`);
    }
    
    text = text.trim();
    
    if (required && !text) {
        throw new Error(`${fieldName} cannot be empty`);
    }
    
    if (text.length > maxLength) {
        throw new Error(`${fieldName} cannot exceed ${maxLength} characters`);
    }
    
    return text;
}


/**
 * Stash Tile DOM Element Factory
 * 
 * Creates the HTML structure for individual bookmark/link tiles within categories
 * Each tile contains the link info, icon, drag handle, and action buttons
 * 
 * @param {Object} options - Configuration object for the tile
 * @param {string} options.name - Display name for the bookmark
 * @param {string} options.url - Target URL for the bookmark
 * @param {string} options.icon - Icon URL (optional)
 * @returns {HTMLElement} Complete stash tile element ready for insertion
 */
function createStashTile({ name, url, icon }) {
    const tile = document.createElement('div');
    tile.className = 'stash-tile group relative flex items-center p-3 rounded-md shadow-sm bg-gray-700/60 hover:bg-gray-600/80 transition-all duration-200';
    
    // Store data attributes for later retrieval and editing
    tile.dataset.name = name || '';
    tile.dataset.url = url || '';
    tile.dataset.icon = icon || '';
    
    // Generate icon HTML with error handling for broken images
    const iconHtml = icon ? `<img src="${escapeHtml(icon)}" class="stash-icon mr-3 rounded" onerror="this.style.display='none'">` : '';
    
    // Build complete tile structure with drag handle and action buttons
    tile.innerHTML = `
        <div class="stash-drag-handle cursor-move pr-2 text-gray-500 hover:text-gray-400 transition-all duration-200">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                <path d="M3 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zM3 10a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zM3 16a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1z"></path>
            </svg>
        </div>
        
        <div class="flex items-center flex-grow min-w-0">
            ${iconHtml}
            <span class="font-semibold text-white truncate flex-grow">${escapeHtml(name)}</span>
        </div>
        
        <div class="absolute right-0 top-1/2 -translate-y-1/2 pr-2 flex items-center opacity-0 group-hover:opacity-100 transition-all duration-200">
            <button type="button" 
                    class="item-action-btn text-blue-400 hover:text-blue-300 hover:bg-blue-500/20 p-2 rounded-md transition-all duration-200" 
                    data-action="edit-stash" 
                    title="Edit Link"
                    aria-label="Edit ${escapeHtml(name)}">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.5L16.732 3.732z" />
                </svg>
            </button>
            
            <button type="button" 
                    class="item-action-btn text-red-400 hover:text-red-300 hover:bg-red-500/20 p-2 rounded-md transition-all duration-200 ml-1" 
                    data-action="delete-stash" 
                    title="Delete Link"
                    aria-label="Delete ${escapeHtml(name)}">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                </svg>
            </button>
        </div>
    `;
    return tile;
}


/**
 * Category Card DOM Element Factory
 * 
 * Creates the HTML structure for category cards that contain multiple stash tiles
 * Each card has a header with title, icon, and action buttons, plus a sortable list area
 * 
 * @param {Object} options - Configuration object for the category
 * @param {string} options.title - Category display name
 * @param {string} options.icon - Category icon URL (optional)
 * @param {string} options.baseUrl - Base URL for relative links in this category
 * @param {string} options.color - Custom accent color for category and links
 * @param {number} options.x - Horizontal position on canvas
 * @param {number} options.y - Vertical position on canvas
 * @returns {HTMLElement} Complete category card element ready for insertion
 */
function createCategoryCard({ title, icon, baseUrl, color, x = CONFIG.CANVAS.CENTER_X + CONFIG.CANVAS.DEFAULT_OFFSET, y = CONFIG.CANVAS.CENTER_Y + CONFIG.CANVAS.DEFAULT_OFFSET }) {
    const card = document.createElement('div');
    card.className = 'card-window rounded-lg p-4 shadow-lg flex flex-col border border-gray-600/50 hover:border-gray-500/70 transition-all duration-200 backdrop-blur-md';
    
    // Store category metadata for later retrieval and editing
    card.dataset.categoryTitle = title || '';
    card.dataset.categoryIcon = icon || '';
    card.dataset.categoryBaseUrl = baseUrl || '';
    card.dataset.categoryColor = color || '#3b82f6';
    
    // Position the card on the canvas with bounds checking
    card.style.left = `${Math.max(0, x)}px`;
    card.style.top = `${Math.max(0, y)}px`;

    // Apply custom color CSS variables if color is set
    if (color && color !== '#3b82f6') {
        const r = parseInt(color.slice(1, 3), 16);
        const g = parseInt(color.slice(3, 5), 16);
        const b = parseInt(color.slice(5, 7), 16);
        card.style.setProperty('--category-color', color);
        card.style.setProperty('--category-color-rgb', `${r}, ${g}, ${b}`);
    }

    // Generate icon HTML with error handling for broken images
    const iconHtml = icon ? `<img src="${escapeHtml(icon)}" alt="" class="h-6 w-6 mr-2" onerror="this.style.display='none'">` : '';

    // Build complete card structure with drag handle, title, and action buttons
    card.innerHTML = `
        <div class="drag-handle flex justify-between items-center mb-2 pb-2 border-b border-gray-600/50 cursor-move hover:border-gray-500 transition-colors">
            <div class="flex items-center">
                <div class="drag-indicator mr-3 text-gray-500 hover:text-gray-400 transition-colors">
                    <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
                        <path d="M7 2a2 2 0 00-2 2v12a2 2 0 002 2h6a2 2 0 002-2V4a2 2 0 00-2-2H7zM8 4h4v2H8V4zm0 4h4v2H8V8zm0 4h4v2H8v-2z"></path>
                    </svg>
                </div>
                <h2 class="text-xl font-bold text-white flex items-center">
                    ${iconHtml}
                    <span>${escapeHtml(title)}</span>
                </h2>
            </div>
            
            <div class="flex items-center space-x-2">
                <button type="button" 
                        class="action-btn bg-green-600/80 hover:bg-green-600 text-white p-1 rounded-lg transition-all duration-200 hover:scale-110 shadow-lg" 
                        data-action="add-stash" 
                        title="Add Link"
                        aria-label="Add link to ${escapeHtml(title)}">
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
                    </svg>
                </button>
                
                <button type="button" 
                        class="action-btn bg-blue-600/80 hover:bg-blue-600 text-white p-1 rounded-lg transition-all duration-200 hover:scale-110 shadow-lg" 
                        data-action="edit-category" 
                        title="Edit Category"
                        aria-label="Edit category ${escapeHtml(title)}">
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.5L16.732 3.732z" />
                    </svg>
                </button>
                
                <button type="button" 
                        class="action-btn bg-red-600/80 hover:bg-red-600 text-white p-1 rounded-lg transition-all duration-200 hover:scale-110 shadow-lg" 
                        data-action="delete-category" 
                        title="Delete Category"
                        aria-label="Delete category ${escapeHtml(title)}">
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                    </svg>
                </button>
            </div>
        </div>
        
        <div class="stash-list flex flex-col space-y-2 flex-grow min-h-0" role="list" aria-label="Links in ${escapeHtml(title)}">
        </div>
    `;
    return card;
}


/**
 * HTML Sanitization Function
 * 
 * Prevents XSS attacks by escaping HTML special characters in user input
 * Always use this function before inserting user-provided text into innerHTML
 * 
 * @param {string} unsafe - Raw user input that may contain HTML
 * @returns {string} HTML-safe escaped text
 */
function escapeHtml(unsafe) {
    if (!unsafe) return '';
    return unsafe
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "'");
}


/**
 * Safe DOM Element Retrieval
 * 
 * Safely retrieves DOM elements by ID with error handling
 * Prevents crashes when expected elements are not found
 * 
 * @param {string} id - Element ID to retrieve
 * @returns {HTMLElement|null} Element if found, null if not found or error occurs
 */
function safeGetElementById(id) {
    try {
        return document.getElementById(id);
    } catch (error) {
        console.error(`Error getting element by ID "${id}":`, error);
        return null;
    }
}


/**
 * Category Edit Handler
 * 
 * Processes category edit form submissions, validates input, checks for conflicts,
 * and updates both the DOM element and its visual representation
 * 
 * @param {HTMLElement} cardElement - The category card DOM element to update
 * @param {Array} dashboardData - Current dashboard data for conflict checking
 */
export function editCategory(cardElement, dashboardData) {
    if (!cardElement) {
        showAlert('Category element not found.');
        return;
    }

    try {
        const oldTitle = cardElement.dataset.categoryTitle;
        
        // Retrieve form input elements
        const titleInput = safeGetElementById('edit-category-title');
        const iconInput = safeGetElementById('edit-category-icon');
        const baseUrlInput = safeGetElementById('edit-category-base-url');
        const colorInput = safeGetElementById('edit-category-color-hex');

        if (!titleInput) {
            showAlert('Title input field not found.');
            return;
        }

        // Validate all form inputs according to configured limits
        const newTitle = validateText(titleInput.value, 'Category title', CONFIG.VALIDATION.MAX_TITLE_LENGTH);
        const newIcon = iconInput ? validateText(iconInput.value, 'Icon URL', CONFIG.VALIDATION.MAX_ICON_URL_LENGTH, false) : '';
        const newBaseUrl = baseUrlInput ? validateText(baseUrlInput.value, 'Base URL', CONFIG.VALIDATION.MAX_URL_LENGTH, false) : '';

        // Validate URLs if provided (optional fields)
        if (newIcon) {
            validateUrl(newIcon);
        }
        if (newBaseUrl) {
            validateUrl(newBaseUrl);
        }
        
        // Get and validate color
        const newColor = colorInput ? colorInput.value : '#3b82f6';
        if (newColor && !/^#[0-9A-Fa-f]{6}$/.test(newColor)) {
            showAlert('Invalid color format. Please use #RRGGBB format.');
            return;
        }
        
        // Check for title conflicts with other categories
        const titleConflict = dashboardData.some(c => c.title !== oldTitle && c.title === newTitle);
        if (titleConflict) {
            showAlert(`Category with title "${newTitle}" already exists.`);
            return;
        }

        // Update the card's data attributes
        cardElement.dataset.categoryTitle = newTitle;
        cardElement.dataset.categoryIcon = newIcon;
        cardElement.dataset.categoryBaseUrl = newBaseUrl;
        cardElement.dataset.categoryColor = newColor;

        // Apply updated color CSS variables
        if (newColor && newColor !== '#3b82f6') {
            const r = parseInt(newColor.slice(1, 3), 16);
            const g = parseInt(newColor.slice(3, 5), 16);
            const b = parseInt(newColor.slice(5, 7), 16);
            cardElement.style.setProperty('--category-color', newColor);
            cardElement.style.setProperty('--category-color-rgb', `${r}, ${g}, ${b}`);
        } else {
            cardElement.style.removeProperty('--category-color');
            cardElement.style.removeProperty('--category-color-rgb');
        }

        if (window.applyCategoryColors) {
            window.applyCategoryColors();
        }

        // Update the visible title text in the DOM
        const titleElement = cardElement.querySelector('h2 > span');
        const iconContainer = cardElement.querySelector('h2'); 
        let oldIcon = iconContainer.querySelector('img');

        if (titleElement) {
            titleElement.textContent = newTitle;
        }

        // Handle icon updates: add, update, or remove
        if (newIcon) {
            if (oldIcon) {
                oldIcon.src = newIcon;
                oldIcon.style.display = '';
            } else {
                const newIconImg = document.createElement('img');
                newIconImg.src = newIcon;
                newIconImg.alt = "";
                newIconImg.className = "h-6 w-6 mr-2";
                newIconImg.onerror = function() { this.style.display = 'none'; };
                iconContainer.insertBefore(newIconImg, titleElement);
            }
        } else if (oldIcon) {
            oldIcon.remove();
        }
        
        closeModal();
    } catch (error) {
        console.error('Error editing category:', error);
        showAlert(`Error updating category: ${error.message}`);
    }
}


/**
 * Category Deletion Handler
 * 
 * Removes a category card from the dashboard
 * The card element is completely removed from the DOM
 * 
 * @param {HTMLElement} btn - Delete button that was clicked
 */
export function deleteCategory(btn) {
    try {
        const cardElement = btn.closest('.card-window');
        if (cardElement) {
            cardElement.remove();
        }
    } catch (error) {
        console.error('Error deleting category:', error);
        showAlert('Error deleting category. Please try again.');
    }
}


/**
 * Category Creation Handler
 * 
 * Creates a new category from form input, validates the data, creates the DOM element,
 * and positions it on the canvas with drag/drop functionality enabled
 */
export function addCategory() {
    try {
        // Retrieve form input elements
        const titleInput = safeGetElementById('add-category-title');
        const iconInput = safeGetElementById('add-category-icon');
        const baseUrlInput = safeGetElementById('add-category-base-url');

        if (!titleInput) {
            showAlert('Title input field not found.');
            return;
        }

        // Validate all inputs according to configured limits
        const title = validateText(titleInput.value, 'Category title', CONFIG.VALIDATION.MAX_TITLE_LENGTH);
        const icon = iconInput ? validateText(iconInput.value, 'Icon URL', CONFIG.VALIDATION.MAX_ICON_URL_LENGTH, false) : '';
        const baseUrl = baseUrlInput ? validateText(baseUrlInput.value, 'Base URL', CONFIG.VALIDATION.MAX_URL_LENGTH, false) : '';

        // Validate URLs if provided
        if (icon) validateUrl(icon);
        if (baseUrl) validateUrl(baseUrl);

        // Get category color from color picker
        const color = getCategoryColor('add');

        // Create category data object with default positioning
        const newCategory = { 
            title, 
            icon, 
            baseUrl,
            color,
            x: CONFIG.CANVAS.CENTER_X + CONFIG.CANVAS.DEFAULT_OFFSET, 
            y: CONFIG.CANVAS.CENTER_Y + CONFIG.CANVAS.DEFAULT_OFFSET 
        };
        
        // Create and insert the new category card element
        const cardElement = createCategoryCard(newCategory);
        
        const canvas = document.getElementById('dashboard-canvas');
        if (canvas) {
            canvas.appendChild(cardElement);
            
            // Enable drag and drop functionality for the new card
            makeDraggable(cardElement);
            const stashList = cardElement.querySelector('.stash-list');
            if (stashList) {
                makeSortable(stashList);
            }

            // Scroll the viewport to show the new card
            const wrapper = document.getElementById('dashboard-wrapper');
            if (wrapper) {
                const rect = cardElement.getBoundingClientRect();
                wrapper.scrollLeft = newCategory.x - (wrapper.clientWidth / 2);
                wrapper.scrollTop = newCategory.y - (wrapper.clientHeight / 2);
            }
        }

        if (window.applyCategoryColors) {
            window.applyCategoryColors();
        }

        closeModal();
    } catch (error) {
        console.error('Error adding category:', error);
        showAlert(`Error adding category: ${error.message}`);
    }
}


/**
 * Stash Item Creation Handler
 * 
 * Creates a new bookmark/link within a category from form input
 * Handles URL resolution against the category's base URL
 * 
 * @param {HTMLElement} categoryElement - The category card to add the item to
 */
export function addStash(categoryElement) {
    if (!categoryElement) {
        showAlert('Category element not found.');
        return;
    }

    try {
        // Retrieve form input elements
        const nameInput = safeGetElementById('add-stash-name');
        const urlInput = safeGetElementById('add-stash-url');
        const iconInput = safeGetElementById('add-stash-icon');

        if (!nameInput || !urlInput) {
            showAlert('Required input fields not found.');
            return;
        }

        // Validate form inputs
        const name = validateText(nameInput.value, 'Link name', CONFIG.VALIDATION.MAX_TITLE_LENGTH);
        const urlInputValue = validateText(urlInput.value, 'URL', CONFIG.VALIDATION.MAX_URL_LENGTH);
        const icon = iconInput ? validateText(iconInput.value, 'Icon URL', CONFIG.VALIDATION.MAX_ICON_URL_LENGTH, false) : '';
        const baseUrl = categoryElement.dataset.categoryBaseUrl || '';

        // Resolve the URL against the category's base URL
        const url = resolveUrl(urlInputValue, baseUrl);

        // Validate icon URL if provided
        if (icon) {
            validateUrl(icon);
        }

        // Create the stash data object and DOM element
        const newStash = { name, url, icon };
        
        const listElement = categoryElement.querySelector('.stash-list');
        if (listElement) {
            listElement.appendChild(createStashTile(newStash));
        }
        
        closeModal();
    } catch (error) {
        console.error('Error adding stash:', error);
        showAlert(`Error adding link: ${error.message}`);
    }
}


/**
 * Stash Item Edit Handler
 * 
 * Updates an existing bookmark/link with new information from the edit form
 * Handles URL resolution and icon updates
 * 
 * @param {HTMLElement} stashElement - The stash tile DOM element to update
 */
export function editStash(stashElement) {
    if (!stashElement) {
        showAlert('Stash element not found.');
        return;
    }

    try {
        // Retrieve form input elements
        const nameInput = safeGetElementById('edit-stash-name');
        const urlInput = safeGetElementById('edit-stash-url');
        const iconInput = safeGetElementById('edit-stash-icon');
        
        if (!nameInput || !urlInput) {
            showAlert('Required input fields not found.');
            return;
        }

        // Validate form inputs
        const name = validateText(nameInput.value, 'Link name', CONFIG.VALIDATION.MAX_TITLE_LENGTH);
        const urlInputValue = validateText(urlInput.value, 'URL', CONFIG.VALIDATION.MAX_URL_LENGTH);
        const icon = iconInput ? validateText(iconInput.value, 'Icon URL', CONFIG.VALIDATION.MAX_ICON_URL_LENGTH, false) : '';
        
        // Get the parent category for base URL resolution
        const categoryElement = stashElement.closest('.card-window');
        const baseUrl = categoryElement ? (categoryElement.dataset.categoryBaseUrl || '') : '';

        // Resolve and validate the URL
        const url = resolveUrl(urlInputValue, baseUrl);

        // Validate icon URL if provided
        if (icon) {
            validateUrl(icon);
        }

        // Update the element's data attributes
        stashElement.dataset.name = name;
        stashElement.dataset.url = url;
        stashElement.dataset.icon = icon;

        // Update the visible name text
        const nameSpan = stashElement.querySelector('span.font-semibold');
        if (nameSpan) {
            nameSpan.textContent = name;
        }

        // Handle icon updates: add, update, or remove
        let iconImg = stashElement.querySelector('img.stash-icon');

        if (icon) {
            if (iconImg) {
                iconImg.src = icon;
                iconImg.style.display = '';
            } else {
                const newIconImg = document.createElement('img');
                newIconImg.src = icon;
                newIconImg.className = "stash-icon mr-3 rounded";
                newIconImg.onerror = function() { this.style.display = 'none'; };
                const dragHandle = stashElement.querySelector('.stash-drag-handle');
                if (dragHandle && dragHandle.nextSibling) {
                    stashElement.insertBefore(newIconImg, dragHandle.nextSibling);
                }
            }
        } else if (iconImg) {
            iconImg.remove();
        }
        
        closeModal();
    } catch (error) {
        console.error('Error editing stash:', error);
        showAlert(`Error updating link: ${error.message}`);
    }
}


/**
 * Stash Item Deletion Handler
 * 
 * Removes a bookmark/link tile from its category
 * The tile element is completely removed from the DOM
 * 
 * @param {HTMLElement} btn - Delete button that was clicked
 */
export function deleteStash(btn) {
    try {
        const stashElement = btn.closest('.stash-tile');
        if (stashElement) {
            stashElement.remove();
        }
    } catch (error) {
        console.error('Error deleting stash:', error);
        showAlert('Error deleting link. Please try again.');
    }
}


/**
 * Position Reset Handler
 * 
 * Resets all category cards to default positions near the canvas center
 * Cards are staggered slightly to prevent complete overlap
 */
export function resetPositions() {
    try {
        const cards = document.querySelectorAll('#dashboard-canvas .card-window');
        
        // Reset each card position with slight staggering
        cards.forEach((card, index) => {
            const staggerOffset = index * 20;
            card.style.left = `${CONFIG.CANVAS.CENTER_X + staggerOffset}px`;
            card.style.top = `${CONFIG.CANVAS.CENTER_Y + staggerOffset}px`;
        });
        
        showAlert('All category positions have been reset. Click "Save Dashboard" to confirm changes.');
    } catch (error) {
        console.error('Error resetting positions:', error);
        showAlert('Error resetting positions. Please try again.');
    }
}

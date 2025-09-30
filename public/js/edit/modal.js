// /js/stash/edit/modal.js

/**
 * Modal Dialog Management System
 * 
 * Handles all modal interactions for the stash dashboard editor including:
 * - Category creation, editing, and deletion confirmations
 * - Stash item creation, editing, and deletion confirmations  
 * - Alert messages and user confirmations
 * - Form validation and data sanitization
 * - Automatic favicon detection and URL processing
 */

/**
 * Global State Variables
 * 
 * Manages current modal context and callback handlers across modal operations
 */
let currentEditElement = null;  // Currently selected DOM element being edited
let confirmCallback = null;     // Callback function for confirmation dialogs


/**
 * HTML Content Sanitization
 * 
 * Escapes potentially dangerous HTML characters to prevent XSS attacks
 * Essential for safely displaying user-generated content in modal dialogs
 */
function escapeHtml(unsafe) {
    if (!unsafe) return '';
    return unsafe
         .replace(/&/g, "&amp;")
         .replace(/</g, "&lt;")
         .replace(/>/g, "&gt;")
         .replace(/"/g, "&quot;")
         .replace(/'/g, "&#039;");
}


/**
 * URL Domain Extraction Utility
 * 
 * Extracts the hostname from a given URL for favicon generation
 * Handles both full URLs and domain-only inputs with error handling
 */
export function getDomainFromUrl(url) {
    try {
        if (!url.startsWith('http')) url = 'http://' + url;
        return new URL(url).hostname;
    } catch (e) {
        return '';
    }
}


/**
 * Simple Alert Modal Display
 * 
 * Shows informational messages to users with single OK button
 * Used for validation errors, success messages, and general notifications
 */
export function showAlert(message) {
    const modalContent = document.getElementById('modal-content');
    modalContent.innerHTML = `
    <div class="p-6">
        <p class="text-white mb-4">${message}</p>
        <div class="flex justify-end">
            <button type="button" class="bg-blue-500 hover:bg-blue-600 text-white font-bold py-2 px-4 rounded" onclick="closeModal()">OK</button>
        </div>
    </div>`;
    document.getElementById('modal').classList.remove('hidden');
}


/**
 * Generic Confirmation Dialog
 * 
 * Displays yes/no confirmation with custom message and callback handling
 * Used for general confirmations that don't require specialized styling
 */
export function showConfirm(message, callback) {
    confirmCallback = callback;
    const modalContent = document.getElementById('modal-content');
    modalContent.innerHTML = `
    <div class="p-6">
        <p class="text-white mb-4">${message}</p>
        <div class="flex justify-end space-x-2">
            <button type="button" class="bg-gray-500 hover:bg-gray-600 text-white font-bold py-2 px-4 rounded" onclick="closeModal()">Cancel</button>
            <button type="button" class="bg-red-500 hover:bg-red-600 text-white font-bold py-2 px-4 rounded" onclick="handleConfirm(true)">OK</button>
        </div>
    </div>`;
    document.getElementById('modal').classList.remove('hidden');
}


/**
 * Category Edit Modal Interface
 * 
 * Displays form for modifying existing category properties including:
 * - Category title/name editing
 * - Icon URL configuration with optional image display
 * - Base URL setting for relative link resolution within category
 */
export function showEditCategoryModal(cardElement, onSaveCallback) {
    currentEditElement = cardElement;
    const title = escapeHtml(cardElement.dataset.categoryTitle);
    const icon = escapeHtml(cardElement.dataset.categoryIcon || '');
    const baseUrl = escapeHtml(cardElement.dataset.categoryBaseUrl || '');
    
    // Create temporary callback handler for form submission
    window.tempSaveHandler = () => onSaveCallback(currentEditElement);

    const modalContent = document.getElementById('modal-content');
    modalContent.innerHTML = `
    <div class="p-6">
        <h3 class="text-xl font-bold text-white mb-4">Edit Category: ${title}</h3>
        <form onsubmit="event.preventDefault(); window.tempSaveHandler();" class="space-y-4">
            <div>
                <label for="edit-category-title" class="block text-sm font-medium text-gray-400">Title</label>
                <input type="text" id="edit-category-title" value="${title}" required
                    class="mt-1 block w-full bg-gray-700 border-gray-600 rounded-md shadow-sm p-2 text-white focus:ring-blue-500 focus:border-blue-500">
            </div>
            <div>
                <label for="edit-category-icon" class="block text-sm font-medium text-gray-400">Icon URL (Optional)</label>
                <input type="url" id="edit-category-icon" value="${icon}"
                    class="mt-1 block w-full bg-gray-700 border-gray-600 rounded-md shadow-sm p-2 text-white focus:ring-blue-500 focus:border-blue-500">
            </div>
            <div>
                <label for="edit-category-base-url" class="block text-sm font-medium text-gray-400">Base URL (Optional)</label>
                <input type="url" id="edit-category-base-url" value="${baseUrl}"
                    class="mt-1 block w-full bg-gray-700 border-gray-600 rounded-md shadow-sm p-2 text-white focus:ring-blue-500 focus:border-blue-500">
            </div>
            <div class="flex justify-end space-x-2 pt-4">
                <button type="button" class="bg-gray-500 hover:bg-gray-600 text-white font-bold py-2 px-4 rounded" onclick="closeModal()">Cancel</button>
                <button type="submit" class="bg-blue-500 hover:bg-blue-600 text-white font-bold py-2 px-4 rounded">Save Changes</button>
            </div>
        </form>
    </div>`;
    document.getElementById('modal').classList.remove('hidden');
}


/**
 * New Category Creation Modal
 * 
 * Provides interface for adding new categories to the dashboard with:
 * - Title input with validation requirements
 * - Optional icon URL for visual category identification  
 * - Optional base URL for relative link functionality
 */
export function showAddCategoryModal(onSaveCallback) {
    currentEditElement = null;
    
    // Setup callback handler for new category creation
    window.tempSaveHandler = () => onSaveCallback();

    const modalContent = document.getElementById('modal-content');
    modalContent.innerHTML = `
    <div class="p-6">
        <h3 class="text-xl font-bold text-white mb-4">Add New Category</h3>
        <form onsubmit="event.preventDefault(); window.tempSaveHandler();" class="space-y-4">
            <div>
                <label for="add-category-title" class="block text-sm font-medium text-gray-400">Title</label>
                <input type="text" id="add-category-title" required
                    class="mt-1 block w-full bg-gray-700 border-gray-600 rounded-md shadow-sm p-2 text-white focus:ring-blue-500 focus:border-blue-500">
            </div>
            <div>
                <label for="add-category-icon" class="block text-sm font-medium text-gray-400">Icon URL (Optional)</label>
                <input type="url" id="add-category-icon"
                    class="mt-1 block w-full bg-gray-700 border-gray-600 rounded-md shadow-sm p-2 text-white focus:ring-blue-500 focus:border-blue-500">
            </div>
            <div>
                <label for="add-category-base-url" class="block text-sm font-medium text-gray-400">Base URL (Optional)</label>
                <input type="url" id="add-category-base-url"
                    class="mt-1 block w-full bg-gray-700 border-gray-600 rounded-md shadow-sm p-2 text-white focus:ring-blue-500 focus:border-blue-500">
            </div>
            <div class="flex justify-end space-x-2 pt-4">
                <button type="button" class="bg-gray-500 hover:bg-gray-600 text-white font-bold py-2 px-4 rounded" onclick="closeModal()">Cancel</button>
                <button type="submit" class="bg-green-500 hover:bg-green-600 text-white font-bold py-2 px-4 rounded">Add Category</button>
            </div>
        </form>
    </div>`;
    document.getElementById('modal').classList.remove('hidden');
}


/**
 * New Stash Item Creation Modal
 * 
 * Interface for adding bookmark links to existing categories featuring:
 * - Link name and URL input with validation
 * - Automatic favicon detection from URL domains
 * - Base URL awareness for relative/absolute link handling
 * - Real-time icon preview functionality
 */
export function showAddStashModal(categoryElement, onSaveCallback) {
    currentEditElement = categoryElement; 
    
    // Extract base URL from parent category for relative link support
    const baseUrl = categoryElement.dataset.categoryBaseUrl || '';
    
    // Setup save callback with category context
    window.tempSaveHandler = () => onSaveCallback(currentEditElement);
    
    /**
     * Automatic Favicon Detection
     * 
     * Extracts domain from URL input and generates Google favicon service URL
     * Updates both the input field and preview image for immediate feedback
     */
    window.autofillStashIcon = function() {
        const url = document.getElementById('add-stash-url').value.trim();
        const iconInput = document.getElementById('add-stash-icon');
        const domain = getDomainFromUrl(url);
        
        if (domain) {
            const faviconUrl = `https://s2.googleusercontent.com/s2/favicons?domain=${domain}&sz=64`;
            iconInput.value = faviconUrl;
            document.getElementById('add-stash-favicon-preview').src = faviconUrl;
        } else {
            iconInput.value = '';
            document.getElementById('add-stash-favicon-preview').src = 'data:image/gif;base64,R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs=';
        }
    };

    const modalContent = document.getElementById('modal-content');
    modalContent.innerHTML = `
    <div class="p-6">
        <h3 class="text-xl font-bold text-white mb-4">Add Link to "${categoryElement.dataset.categoryTitle}"</h3>
        <form onsubmit="event.preventDefault(); window.tempSaveHandler();" class="space-y-4">
            <div>
                <label for="add-stash-name" class="block text-sm font-medium text-gray-400">Name</label>
                <input type="text" id="add-stash-name" required
                    class="mt-1 block w-full bg-gray-700 border-gray-600 rounded-md shadow-sm p-2 text-white focus:ring-blue-500 focus:border-blue-500">
            </div>
            <div>
                <label for="add-stash-url" class="block text-sm font-medium text-gray-400">URL (${baseUrl ? `Relative to: ${baseUrl}` : 'Full URL'})</label>
                <input type="text" id="add-stash-url" required
                    class="mt-1 block w-full bg-gray-700 border-gray-600 rounded-md shadow-sm p-2 text-white focus:ring-blue-500 focus:border-blue-500">
            </div>
            <div>
                <label for="add-stash-icon" class="block text-sm font-medium text-gray-400">Icon URL (Optional)</label>
                <div class="flex items-center space-x-2">
                    <input type="url" id="add-stash-icon" oninput="document.getElementById('add-stash-favicon-preview').src = this.value || 'data:image/gif;base64,R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs=';"
                        class="mt-1 block w-full bg-gray-700 border-gray-600 rounded-md shadow-sm p-2 text-white focus:ring-blue-500 focus:border-blue-500">
                    <button type="button" onclick="autofillStashIcon()" class="mt-1 p-2 bg-gray-600 hover:bg-gray-500 rounded-md" title="Autofill Icon from URL">
                        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-gray-200" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M4 2a1 1 0 011 1v2.101a7.002 7.002 0 0111.601 2.566 1 1 0 11-1.885.666A5.002 5.002 0 005.999 7H9a1 1 0 010 2H4a1 1 0 01-1-1V3a1 1 0 011-1zm12 14a1 1 0 01-1-1v-2.101a7.002 7.002 0 01-11.601-2.566 1 1 0 111.885-.666A5.002 5.002 0 0014.001 13H11a1 1 0 110-2h5a1 1 0 011 1v5a1 1 0 01-1 1z" clip-rule="evenodd" /></svg>
                    </button>
                </div>
                <div class="mt-2">
                    <img id="add-stash-favicon-preview" src="data:image/gif;base64,R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs=" onerror="this.onerror=null;this.src='data:image/gif;base64,R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs=';" class="w-8 h-8 object-contain bg-gray-700 rounded-md p-1">
                </div>
            </div>
            <div class="flex justify-end space-x-2 pt-4">
                <button type="button" class="bg-gray-500 hover:bg-gray-600 text-white font-bold py-2 px-4 rounded" onclick="closeModal()">Cancel</button>
                <button type="submit" class="bg-green-500 hover:bg-green-600 text-white font-bold py-2 px-4 rounded">Add Link</button>
            </div>
        </form>
    </div>`;
    document.getElementById('modal').classList.remove('hidden');
}


/**
 * Stash Item Edit Modal Interface
 * 
 * Allows modification of existing bookmark links with features:
 * - Pre-populated form fields with current values
 * - Name, URL, and icon editing capabilities
 * - Favicon auto-detection and preview updates
 * - Robust attribute retrieval for malformed HTML handling
 */
export function showEditStashModal(stashElement, onSaveCallback) {
    currentEditElement = stashElement;
    
    // Use getAttribute for robust data extraction from potentially malformed HTML
    const name = escapeHtml(stashElement.getAttribute('data-name'));
    const url = escapeHtml(stashElement.getAttribute('data-url'));
    const icon = escapeHtml(stashElement.getAttribute('data-icon') || '');

    // Extract base URL from parent category for relative link context
    const categoryElement = stashElement.closest('.card-window');
    const baseUrl = categoryElement ? (categoryElement.dataset.categoryBaseUrl || '') : '';

    // Setup callback handler with current element context
    window.tempSaveHandler = () => onSaveCallback(currentEditElement);
    
    /**
     * Edit Mode Favicon Auto-Detection
     * 
     * Similar to add mode but operates on existing edit form elements
     * Provides same domain extraction and Google favicon service integration
     */
    window.autofillStashIcon = function() {
        const urlInput = document.getElementById('edit-stash-url');
        const iconInput = document.getElementById('edit-stash-icon');
        const domain = getDomainFromUrl(urlInput.value.trim());
        
        if (domain) {
            const faviconUrl = `https://s2.googleusercontent.com/s2/favicons?domain=${domain}&sz=64`;
            iconInput.value = faviconUrl;
            document.getElementById('edit-stash-favicon-preview').src = faviconUrl;
        } else {
            iconInput.value = '';
            document.getElementById('edit-stash-favicon-preview').src = 'data:image/gif;base64,R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs=';
        }
    };
    
    const modalContent = document.getElementById('modal-content');
    modalContent.innerHTML = `
    <div class="p-6">
        <h3 class="text-xl font-bold text-white mb-4">Edit Link: ${name}</h3>
        <form onsubmit="event.preventDefault(); window.tempSaveHandler();" class="space-y-4">
            <div>
                <label for="edit-stash-name" class="block text-sm font-medium text-gray-400">Name</label>
                <input type="text" id="edit-stash-name" value="${name}" required
                    class="mt-1 block w-full bg-gray-700 border-gray-600 rounded-md shadow-sm p-2 text-white focus:ring-blue-500 focus:border-blue-500">
            </div>
            <div>
                <label for="edit-stash-url" class="block text-sm font-medium text-gray-400">URL (${baseUrl ? `Relative to: ${baseUrl}` : 'Full URL'})</label>
                <input type="text" id="edit-stash-url" value="${url}" required
                    class="mt-1 block w-full bg-gray-700 border-gray-600 rounded-md shadow-sm p-2 text-white focus:ring-blue-500 focus:border-blue-500">
            </div>
            <div>
                <label for="edit-stash-icon" class="block text-sm font-medium text-gray-400">Icon URL (Optional)</label>
                <div class="flex items-center space-x-2">
                    <input type="url" id="edit-stash-icon" value="${icon}" 
                        oninput="document.getElementById('edit-stash-favicon-preview').src = this.value || 'data:image/gif;base64,R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs=';"
                        class="mt-1 block w-full bg-gray-700 border-gray-600 rounded-md shadow-sm p-2 text-white focus:ring-blue-500 focus:border-blue-500">
                    <button type="button" onclick="autofillStashIcon()" class="mt-1 p-2 bg-gray-600 hover:bg-gray-500 rounded-md" title="Autofill Icon from URL">
                        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-gray-200" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M4 2a1 1 0 011 1v2.101a7.002 7.002 0 0111.601 2.566 1 1 0 11-1.885.666A5.002 5.002 0 005.999 7H9a1 1 0 010 2H4a1 1 0 01-1-1V3a1 1 0 011-1zm12 14a1 1 0 01-1-1v-2.101a7.002 7.002 0 01-11.601-2.566 1 1 0 111.885-.666A5.002 5.002 0 0014.001 13H11a1 1 0 110-2h5a1 1 0 011 1v5a1 1 0 01-1 1z" clip-rule="evenodd" /></svg>
                    </button>
                </div>
                <div class="mt-2">
                    <img id="edit-stash-favicon-preview" src="${icon || 'data:image/gif;base64,R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs='}" onerror="this.onerror=null;this.src='data:image/gif;base64,R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs=';" class="w-8 h-8 object-contain bg-gray-700 rounded-md p-1">
                </div>
            </div>
            <div class="flex justify-end space-x-2 pt-4">
                <button type="button" class="bg-gray-500 hover:bg-gray-600 text-white font-bold py-2 px-4 rounded" onclick="closeModal()">Cancel</button>
                <button type="submit" class="bg-blue-500 hover:bg-blue-600 text-white font-bold py-2 px-4 rounded">Save Changes</button>
            </div>
        </form>
    </div>`;
    document.getElementById('modal').classList.remove('hidden');
}


/**
 * Modal Cleanup and Closure Handler
 * 
 * Performs comprehensive cleanup when closing modals including:
 * - Hiding modal overlay and content
 * - Clearing global state variables
 * - Removing temporary callback handlers
 * - Preventing memory leaks from event handlers
 */
export function closeModal() {
    document.getElementById('modal').classList.add('hidden');
    currentEditElement = null;
    confirmCallback = null;
    if (window.tempSaveHandler) delete window.tempSaveHandler;
    if (window.autofillStashIcon) delete window.autofillStashIcon;
}


/**
 * Confirmation Dialog Response Handler
 * 
 * Processes user responses from confirmation dialogs
 * Executes stored callbacks with user's confirmation status
 */
export function handleConfirm(confirmed) {
    if (confirmCallback) confirmCallback(confirmed);
    closeModal();
}

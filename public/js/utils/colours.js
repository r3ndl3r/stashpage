// /js/utils/colours.js

/**
 * Category Color Utilities
 * 
 * Shared functions for applying custom category colors across
 * both view and edit modes. Centralizes color application logic
 * to prevent duplication and ensure consistency.
 */

/**
 * Apply custom colors to all category cards on the page
 * 
 * This function scans all category cards and applies custom color styling
 * including gradients, borders, and tile accents. It handles both custom
 * colors and default color resets.
 */
export function applyCategoryColors() {
    document.querySelectorAll('.card-window[data-category-color]').forEach(card => {
        const color = card.dataset.categoryColor;
        
        // Skip if no color or default blue
        if (!color || color === '#3b82f6') {
            resetCategoryColors(card);
            return;
        }
        
        // Apply custom color styling
        applyCategoryCustomColor(card, color);
    });
}

/**
 * Reset category card to default styling
 * 
 * Removes all inline color styles, allowing CSS defaults to take over.
 * Used when reverting to the default blue color.
 * 
 * @param {HTMLElement} card - The category card element
 */
function resetCategoryColors(card) {
    // Reset card styles
    card.style.background = '';
    card.style.backdropFilter = '';
    card.style.borderColor = '';
    card.style.borderWidth = '';
    
    // Reset header styles
    const header = card.querySelector('.drag-handle');
    if (header) {
        header.style.borderBottomColor = '';
        header.style.borderBottomWidth = '';
    }
    
    // Reset tile styles
    card.querySelectorAll('.stash-tile').forEach(tile => {
        tile.style.border = '';
        tile.style.borderLeft = '';
        tile.style.borderRadius = '';
        tile.style.background = '';
    });
}

/**
 * Apply custom color styling to category card
 * 
 * Applies gradient backgrounds, colored borders, and tile accents
 * using the provided hex color value.
 * 
 * @param {HTMLElement} card - The category card element
 * @param {string} color - Hex color value (e.g., '#ff5733')
 */
function applyCategoryCustomColor(card, color) {
    // Normalize color format (add # if missing)
    const hexColor = color.startsWith('#') ? color : '#' + color;
    
    // Convert hex to RGB for transparency effects
    const r = parseInt(hexColor.slice(1, 3), 16);
    const g = parseInt(hexColor.slice(3, 5), 16);
    const b = parseInt(hexColor.slice(5, 7), 16);
    
    // Apply colored background gradient
    card.style.background = `linear-gradient(315deg,
        rgba(${r}, ${g}, ${b}, 0.35) 0%,
        rgba(${r}, ${g}, ${b}, 0.20) 50%,
        rgba(0, 0, 0, 0.7) 100%)`;
    
    // Maintain backdrop blur
    card.style.backdropFilter = 'blur(10px)';
    
    // Apply colored border to card
    card.style.borderColor = hexColor;
    card.style.borderWidth = '1px';
    
    // Apply colored border to header
    const header = card.querySelector('.drag-handle');
    if (header) {
        header.style.borderBottomColor = hexColor;
        header.style.borderBottomWidth = '1px';
    }
    
    // Apply full border + thick left accent to bookmark tiles
    card.querySelectorAll('.stash-tile').forEach(tile => {
        tile.style.border = `1px solid ${hexColor}`;
        tile.style.borderLeft = `4px solid ${hexColor}`;
        tile.style.borderRadius = '4px';
        tile.style.background = `linear-gradient(90deg, 
            rgba(${r}, ${g}, ${b}, 0.03) 0%, 
            rgba(${r}, ${g}, ${b}, 0.015) 50%, 
            rgba(30, 41, 59, 0.9) 100%)`;
    });
}

/**
 * Normalize color format to ensure consistency
 * 
 * Ensures color is in lowercase hex format with # prefix.
 * Returns default blue if validation fails.
 * 
 * @param {string} color - Color value to normalize
 * @returns {string} Normalized hex color
 */
export function normalizeColor(color) {
    // Default if missing or empty
    if (!color) return '#3b82f6';
    
    // Remove whitespace
    color = color.replace(/\s+/g, '');
    
    // Convert to lowercase
    color = color.toLowerCase();
    
    // Add # prefix if missing
    if (!color.startsWith('#')) {
        color = '#' + color;
    }
    
    // Validate hex format (6 characters after #)
    if (!/^#[0-9a-f]{6}$/.test(color)) {
        return '#3b82f6';
    }
    
    return color;
}

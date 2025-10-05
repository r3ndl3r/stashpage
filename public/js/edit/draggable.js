// /js/edit/draggable.js

/**
 * Draggable Functionality Module
 * 
 * This module provides drag-and-drop functionality for dashboard categories and sortable
 * functionality for stash items within categories. It handles:
 * - Card dragging with performance optimizations
 * - Memory management and event listener cleanup
 * - Touch and mouse interaction support
 * - Integration with Sortable.js for item reordering
 * 
 * Dependencies:
 * - Sortable.js: External library for drag-and-drop sorting within lists
 * 
 * Usage:
 * - makeDraggable(cardElement): Makes a category card draggable
 * - makeSortable(listElement): Makes a stash list sortable
 * - cleanupAllDragInstances(): Cleans up all drag functionality (for SPA cleanup)
 */

/**
 * Global Drag State Management
 * 
 * Centralized state object that tracks all active drag operations and instances
 * This prevents memory leaks and ensures proper cleanup of event listeners
 */
const DragState = {
    activeCard: null,                   // Currently dragged card element
    isDragging: false,                  // Whether a drag operation is in progress
    dragListeners: new Map(),           // Maps card IDs to their event listeners for cleanup
    sortableInstances: new WeakMap(),   // Tracks Sortable.js instances for proper disposal
    rafId: null                         // RequestAnimationFrame ID for performance optimization
};

/**
 * Drag Configuration Constants
 * 
 * These values control the behavior and performance characteristics of the drag system
 * Modify these to adjust sensitivity, performance thresholds, and visual feedback
 */
const DRAG_CONFIG = {
    MINIMUM_DRAG_DISTANCE: 5,           // Pixels to move before starting drag (prevents accidental drags)
    DRAG_THRESHOLD_TIME: 100,           // Milliseconds to wait before drag starts
    ANIMATION_DURATION: 200,            // Duration for drag-related animations
    Z_INDEX_DRAGGING: 1000,             // Z-index for dragged elements
    PERFORMANCE_MODE_THRESHOLD: 10,     // Number of cards before enabling performance optimizations
    GRID_SNAP_ENABLED: true,            // Whether to snap card positions to grid during drag
    GRID_SIZE: 20,                      // Grid cell size in pixels for snapping alignment
    GRID_VISUAL_ENABLED: true           // Show visual grid overlay during drag operations
};

/**
 * Event Listener Cleanup System
 * 
 * Safely removes all event listeners associated with a draggable card
 * This prevents memory leaks when cards are removed or when cleanup is needed
 * 
 * @param {HTMLElement} element - The card element (not used directly, but kept for API consistency)
 * @param {string} cardId - Unique identifier for the card to clean up
 */
function cleanupListeners(element, cardId) {
    try {
        const listeners = DragState.dragListeners.get(cardId);
        if (listeners) {
            // Remove each event listener that was registered for this card
            listeners.forEach(({ event, handler }) => {
                document.removeEventListener(event, handler);
            });
            DragState.dragListeners.delete(cardId);
        }
    } catch (error) {
        console.error('Error cleaning up drag listeners:', error);
    }
}

/**
 * Unique Identifier Generation
 * 
 * Generates and stores a unique ID for each draggable element
 * This ID is used for tracking event listeners and ensuring proper cleanup
 * 
 * @param {HTMLElement} element - Element to generate/retrieve ID for
 * @returns {string} Unique identifier for the element
 */
function generateCardId(element) {
    if (!element.dataset.cardId) {
        element.dataset.cardId = `card-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
    }
    return element.dataset.cardId;
}

/**
 * Optimized Transform Application with Grid Snapping
 * 
 * Uses RequestAnimationFrame to apply CSS transforms smoothly during drag operations
 * Includes optional grid snapping for precise alignment of dragged elements
 * 
 * @param {HTMLElement} element - Element to transform
 * @param {number} x - Horizontal position in pixels
 * @param {number} y - Vertical position in pixels
 */
function applyTransform(element, x, y) {
    // Cancel any pending animation frame to avoid conflicts
    if (DragState.rafId) {
        cancelAnimationFrame(DragState.rafId);
    }
    
    // Schedule the transform application for the next frame
    DragState.rafId = requestAnimationFrame(() => {
        if (element && DragState.isDragging) {
            // Apply grid snapping calculations if feature is enabled
            if (DRAG_CONFIG.GRID_SNAP_ENABLED) {
                // Round coordinates to nearest grid intersection
                x = Math.round(x / DRAG_CONFIG.GRID_SIZE) * DRAG_CONFIG.GRID_SIZE;
                y = Math.round(y / DRAG_CONFIG.GRID_SIZE) * DRAG_CONFIG.GRID_SIZE;
            }
            
            // Use translate3d for hardware acceleration and prevent negative positions
            element.style.transform = `translate3d(${Math.max(0, x)}px, ${Math.max(0, y)}px, 0)`;
        }
    });
}

/**
 * Performance Mode Toggle
 * 
 * Enables/disables performance optimizations during drag operations
 * When many cards are present, this temporarily disables expensive visual effects
 * 
 * @param {boolean} enable - Whether to enable performance mode
 */
function setPerformanceMode(enable) {
    const body = document.body;
    if (enable) {
        body.classList.add('dragging-active');
        // Temporarily disable transitions on non-dragged cards for better performance
        document.querySelectorAll('.card-window:not(.card-dragging)').forEach(card => {
            card.style.transition = 'none';
        });
    } else {
        body.classList.remove('dragging-active');
        // Re-enable transitions after drag completes
        document.querySelectorAll('.card-window').forEach(card => {
            card.style.transition = '';
        });
    }
}

/**
 * Main Draggable Implementation
 * 
 * Makes a category card draggable by attaching mouse event handlers to its drag handle
 * Includes performance optimizations, memory management, and accessibility features
 * 
 * @param {HTMLElement} card - The category card element to make draggable
 */
export function makeDraggable(card) {
    if (!card) {
        console.error('makeDraggable: card element is required');
        return;
    }

    // Find the drag handle within the card (usually the header area)
    const handle = card.querySelector('.drag-handle');
    if (!handle) {
        console.warn('makeDraggable: No drag handle found in card');
        return;
    }

    const cardId = generateCardId(card);
    
    // Clean up any existing listeners to prevent duplicates
    cleanupListeners(card, cardId);

    // Check if performance optimizations should be enabled
    const totalCards = document.querySelectorAll('.card-window').length;
    const usePerformanceMode = totalCards > DRAG_CONFIG.PERFORMANCE_MODE_THRESHOLD;

    // Drag operation state - resets for each new drag
    let dragData = {
        startX: 0,                      // Initial mouse X position
        startY: 0,                      // Initial mouse Y position
        startTime: 0,                   // When the mouse was pressed
        initialLeft: 0,                 // Card's initial left position
        initialTop: 0,                  // Card's initial top position
        hasMoved: false                 // Whether the card actually moved during drag
    };

    /**
     * Mouse Down Handler - Drag Initiation
     * 
     * Handles the start of a potential drag operation
     * Records initial positions and sets up move/up listeners
     */
    function handleMouseDown(e) {
        // Ignore clicks on buttons or if already dragging
        if (e.target.tagName === 'BUTTON' || 
            e.target.closest('button') || 
            DragState.isDragging ||
            e.button !== 0) { // Only handle left mouse button
            return;
        }

        e.preventDefault();
        e.stopPropagation();

        // Record initial state for drag calculations
        dragData.startX = e.clientX;
        dragData.startY = e.clientY;
        dragData.startTime = Date.now();
        dragData.hasMoved = false;

        // Calculate current position relative to parent container
        const rect = card.getBoundingClientRect();
        const parentRect = card.offsetParent?.getBoundingClientRect() || { left: 0, top: 0 };

        dragData.initialLeft = rect.left - parentRect.left;
        dragData.initialTop = rect.top - parentRect.top;

        // Set up event listeners for mouse movement and release
        const listeners = [
            { event: 'mousemove', handler: handleMouseMove },
            { event: 'mouseup', handler: handleMouseUp },
            { event: 'selectstart', handler: preventDefault }, // Prevent text selection
            { event: 'dragstart', handler: preventDefault }     // Prevent native drag
        ];

        // Attach listeners to document for global mouse tracking
        listeners.forEach(({ event, handler }) => {
            document.addEventListener(event, handler, { passive: false });
        });

        // Store listeners for cleanup
        DragState.dragListeners.set(cardId, listeners);
    }

    /**
     * Mouse Move Handler - Drag Processing
     * 
     * Handles mouse movement during a potential or active drag operation
     * Implements drag threshold to prevent accidental drags
     */
    function handleMouseMove(moveEvent) {
        if (!DragState.dragListeners.has(cardId)) return;

        const deltaX = moveEvent.clientX - dragData.startX;
        const deltaY = moveEvent.clientY - dragData.startY;
        const distance = Math.sqrt(deltaX * deltaX + deltaY * deltaY);
        const timeDelta = Date.now() - dragData.startTime;

        // Start dragging only after minimum distance/time threshold
        if (!DragState.isDragging && 
            (distance > DRAG_CONFIG.MINIMUM_DRAG_DISTANCE || 
             timeDelta > DRAG_CONFIG.DRAG_THRESHOLD_TIME)) {
            
            startDragging();
        }

        // Update position if currently dragging this card
        if (DragState.isDragging && DragState.activeCard === card) {
            dragData.hasMoved = true;
            const newX = dragData.initialLeft + deltaX;
            const newY = dragData.initialTop + deltaY;
            applyTransform(card, newX, newY);
        }
    }

    /**
     * Mouse Up Handler - Drag Completion
     * 
     * Handles the end of a drag operation and cleanup
     */
    function handleMouseUp() {
        if (DragState.activeCard === card) {
            stopDragging();
        }
        cleanupListeners(card, cardId);
    }

    /**
     * Drag Start Logic
     * 
     * Initializes the drag state and visual feedback
     * Sets up performance optimizations if needed
     */
    function startDragging() {
        DragState.isDragging = true;
        DragState.activeCard = card;

        // Enable performance mode for better frame rates with many cards
        if (usePerformanceMode) {
            setPerformanceMode(true);
        }

        // Apply visual drag state
        card.classList.add('card-dragging');
        showGridOverlay();
        card.style.zIndex = DRAG_CONFIG.Z_INDEX_DRAGGING;
        // Switch to transform-based positioning for smooth movement
        card.style.transform = `translate3d(${dragData.initialLeft}px, ${dragData.initialTop}px, 0)`;
        card.style.left = '0px';
        card.style.top = '0px';

        // Dispatch custom event for other components to react
        card.dispatchEvent(new CustomEvent('dragstart', { 
            detail: { cardId, initialPosition: { x: dragData.initialLeft, y: dragData.initialTop } }
        }));
    }

    /**
     * Drag Stop Logic
     * 
     * Completes the drag operation and restores normal positioning
     * Handles cleanup and final position calculation
     */
    function stopDragging() {
        if (!DragState.activeCard) return;

        const card = DragState.activeCard;

        try {
            // Extract final position from CSS transform matrix
            const computedStyle = window.getComputedStyle(card);
            const transform = computedStyle.transform;
            
            let finalX = dragData.initialLeft;
            let finalY = dragData.initialTop;

            // Parse transform matrix to get actual final position
            if (transform && transform !== 'none') {
                const matrix = new DOMMatrix(transform);
                finalX = matrix.m41;
                finalY = matrix.m42;
            }

            // Apply final position using left/top and reset transform
            card.style.left = `${Math.max(0, finalX)}px`;
            card.style.top = `${Math.max(0, finalY)}px`;
            card.style.transform = '';
            card.style.zIndex = '';
            card.classList.remove('card-dragging');
            hideGridOverlay();

            // Dispatch completion event
            card.dispatchEvent(new CustomEvent('dragend', { 
                detail: { 
                    cardId, 
                    finalPosition: { x: finalX, y: finalY },
                    moved: dragData.hasMoved
                }
            }));

        } catch (error) {
            console.error('Error in stopDragging:', error);
            // Fallback cleanup if matrix parsing fails
            card.style.transform = '';
            card.style.zIndex = '';
            card.classList.remove('card-dragging');
        }

        // Restore normal performance mode
        if (usePerformanceMode) {
            setPerformanceMode(false);
        }

        // Reset global drag state
        DragState.isDragging = false;
        DragState.activeCard = null;

        // Cancel any pending animation frames
        if (DragState.rafId) {
            cancelAnimationFrame(DragState.rafId);
            DragState.rafId = null;
        }
    }

    /**
     * Event Prevention Helper
     * 
     * Prevents default browser behaviors during drag operations
     */
    function preventDefault(e) {
        e.preventDefault();
        return false;
    }

    // Initialize the drag functionality by attaching the mouse down handler
    handle.addEventListener('mousedown', handleMouseDown, { passive: false });

    // Store cleanup function on the element for later use
    card._dragCleanup = () => {
        handle.removeEventListener('mousedown', handleMouseDown);
        cleanupListeners(card, cardId);
        if (DragState.activeCard === card) {
            stopDragging();
        }
    };
}

/**
 * Sortable List Implementation
 * 
 * Makes a stash list sortable using Sortable.js library
 * Handles initialization, configuration, and cleanup of sortable instances
 * 
 * @param {HTMLElement} list - The stash list element to make sortable
 */
export function makeSortable(list) {
    if (!list) {
        console.error('makeSortable: list element is required');
        return;
    }

    if (typeof Sortable === 'undefined') {
        console.error('Sortable.js is required for makeSortable and must be loaded globally.');
        return;
    }

    try {
        // Destroy all Sortable instances
        // Note: WeakMap doesn't have forEach - instances will be garbage collected
        DragState.sortableInstances = new WeakMap();

        // Configure Sortable.js options for optimal user experience
        const sortableOptions = {
            group: 'shared',                        // Allows dragging between different lists
            animation: DRAG_CONFIG.ANIMATION_DURATION, // Smooth animation during reordering
            handle: '.stash-drag-handle',           // Only the drag handle can initiate drag
            draggable: '.stash-tile',               // Only tiles can be dragged
            delay: 100,                             // Slight delay before drag starts
            delayOnTouchOnly: true,                 // Delay only applies to touch devices
            filter: 'button[data-action]',          // Exclude action buttons from drag
            preventOnFilter: false,                 // Allow other events on filtered elements
            
            /**
             * Sortable Start Callback
             * 
             * Called when user starts dragging a stash item
             * Applies visual feedback classes
             */
            onStart: function(evt) {
                document.body.classList.add('sortable-active');
                evt.item.classList.add('sortable-dragging');
            },
            
            /**
             * Sortable End Callback
             * 
             * Called when user completes dragging a stash item
             * Cleans up visual feedback and dispatches change events
             */
            onEnd: function(evt) {
                document.body.classList.remove('sortable-active');
                evt.item.classList.remove('sortable-dragging');
                
                // Notify other components about the reorder
                list.dispatchEvent(new CustomEvent('sortablechange', {
                    detail: {
                        item: evt.item,
                        from: evt.from,
                        to: evt.to,
                        oldIndex: evt.oldIndex,
                        newIndex: evt.newIndex
                    }
                }));
            },
            
            /**
             * Sortable Move Callback
             * 
             * Called during drag to determine if drop is allowed
             * Prevents dropping on buttons or other invalid targets
             */
            onMove: function(evt) {
                return !evt.related.matches('button, button *');
            }
        };

        // Create the Sortable instance
        const sortableInstance = new Sortable(list, sortableOptions);
        
        // Store instance for cleanup
        DragState.sortableInstances.set(list, sortableInstance);

        // Store cleanup function on the element
        list._sortableCleanup = () => {
            if (DragState.sortableInstances.has(list)) {
                const instance = DragState.sortableInstances.get(list);
                instance.destroy();
                DragState.sortableInstances.delete(list);
            }
        };

    } catch (error) {
        console.error('Error creating Sortable instance:', error);
    }
}

/**
 * Global Cleanup Function
 * 
 * Cleans up all drag and sortable instances across the entire application
 * Essential for Single Page Applications to prevent memory leaks
 * Should be called when navigating away from the dashboard
 */
export function cleanupAllDragInstances() {
    try {
        // Remove all registered drag event listeners
        DragState.dragListeners.forEach((listeners, cardId) => {
            listeners.forEach(({ event, handler }) => {
                document.removeEventListener(event, handler);
            });
        });
        DragState.dragListeners.clear();

        // Destroy all Sortable instances
        DragState.sortableInstances.forEach((instance) => {
            instance.destroy();
        });
        DragState.sortableInstances = new WeakMap();

        // Reset global drag state
        DragState.activeCard = null;
        DragState.isDragging = false;
        
        // Cancel any pending animation frames
        if (DragState.rafId) {
            cancelAnimationFrame(DragState.rafId);
            DragState.rafId = null;
        }

        // Disable performance mode
        setPerformanceMode(false);

    } catch (error) {
        console.error('Error cleaning up drag instances:', error);
    }
}

/**
 * Individual Element Cleanup
 * 
 * Cleans up drag/sortable functionality for a specific element
 * Used when individual cards or lists are removed from the DOM
 * 
 * @param {HTMLElement} element - Element to clean up
 */
export function cleanupElement(element) {
    if (!element) return;

    try {
        // Clean up drag functionality if present
        if (typeof element._dragCleanup === 'function') {
            element._dragCleanup();
            delete element._dragCleanup;
        }

        // Clean up sortable functionality if present
        if (typeof element._sortableCleanup === 'function') {
            element._sortableCleanup();
            delete element._sortableCleanup;
        }
    } catch (error) {
        console.error('Error cleaning up element:', error);
    }
}

/**
 * Browser Event Handlers for Edge Cases
 * 
 * These handlers ensure proper cleanup and behavior in various browser scenarios
 */

// Global cleanup when page is about to unload (prevents memory leaks)
window.addEventListener('beforeunload', cleanupAllDragInstances);

// Handle tab visibility changes (user switches tabs during drag)
document.addEventListener('visibilitychange', () => {
    if (document.hidden && DragState.isDragging) {
        // Force stop dragging when tab becomes hidden to prevent stuck state
        if (DragState.activeCard) {
            DragState.activeCard.dispatchEvent(new MouseEvent('mouseup'));
        }
    }
});


/**
 * Grid Overlay Management
 * 
 * Creates and manages a visual grid overlay that appears during drag operations
 * to help users align cards precisely to grid intersection points
 */

/**
 * Creates Visual Grid Overlay Element
 * 
 * Generates an SVG-based grid pattern that overlays the canvas during drag operations
 * The grid spacing matches the snap grid size for visual consistency
 * 
 * @returns {HTMLElement} Grid overlay element ready for insertion into DOM
 */
function createGridOverlay() {
    const overlay = document.createElement('div');
    overlay.id = 'grid-overlay';
    overlay.style.position = 'absolute';
    overlay.style.top = '0';
    overlay.style.left = '0';
    overlay.style.width = '100%';
    overlay.style.height = '100%';
    overlay.style.pointerEvents = 'none';         // Allows clicks to pass through
    overlay.style.zIndex = '999';                 // Appears above cards but below dragged element
    overlay.style.opacity = '0.3';               // Subtle visibility to avoid visual clutter
    
    // Create SVG pattern for grid lines
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.style.width = '100%';
    svg.style.height = '100%';
    
    // Define repeating pattern for grid cells
    const defs = document.createElementNS('http://www.w3.org/2000/svg', 'defs');
    const pattern = document.createElementNS('http://www.w3.org/2000/svg', 'pattern');
    pattern.id = 'grid-pattern';
    pattern.setAttribute('width', DRAG_CONFIG.GRID_SIZE);
    pattern.setAttribute('height', DRAG_CONFIG.GRID_SIZE);
    pattern.setAttribute('patternUnits', 'userSpaceOnUse');
    
    // Create grid lines within pattern
    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    path.setAttribute('d', `M ${DRAG_CONFIG.GRID_SIZE} 0 L 0 0 0 ${DRAG_CONFIG.GRID_SIZE}`);
    path.setAttribute('fill', 'none');
    path.setAttribute('stroke', '#ffffff');       // White grid lines
    path.setAttribute('stroke-width', '1');
    
    // Assemble SVG structure
    pattern.appendChild(path);
    defs.appendChild(pattern);
    svg.appendChild(defs);
    
    // Apply pattern to full canvas area
    const rect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
    rect.setAttribute('width', '100%');
    rect.setAttribute('height', '100%');
    rect.setAttribute('fill', 'url(#grid-pattern)');
    svg.appendChild(rect);
    
    overlay.appendChild(svg);
    return overlay;
}


/**
 * Shows Grid Overlay During Drag Operations
 * 
 * Displays the visual grid to help users align cards precisely
 * Only shows when grid visual feature is enabled in configuration
 */
function showGridOverlay() {
    if (!DRAG_CONFIG.GRID_VISUAL_ENABLED) return;
    
    // Check if overlay already exists to prevent duplicates
    if (document.getElementById('grid-overlay')) return;
    
    const canvas = document.getElementById('dashboard-canvas');
    if (canvas) {
        const overlay = createGridOverlay();
        canvas.appendChild(overlay);
    }
}


/**
 * Hides Grid Overlay After Drag Completion
 * 
 * Removes the visual grid when drag operation ends
 * Cleans up DOM to prevent memory leaks
 */
function hideGridOverlay() {
    const overlay = document.getElementById('grid-overlay');
    if (overlay) {
        overlay.remove();
    }
}
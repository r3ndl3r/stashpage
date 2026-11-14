// /js/utils/keyboard.js

/**
 * Keyboard event helpers shared by the dashboard, search, and editor handlers.
 */

/**
 * Check whether a keyboard event belongs to an input method composition.
 *
 * Some browsers report composition only through keyCode 229, so both the
 * standard flag and the legacy key code are checked.
 *
 * @param {KeyboardEvent} event - Keyboard event to inspect
 * @returns {boolean} True while the event is part of an IME composition
 */
export function isComposingKey(event) {
    return Boolean(event.isComposing || event.keyCode === 229);
}

/**
 * Check whether an element accepts text, selection, or option input.
 *
 * @param {Element|null|undefined} element - Element to inspect
 * @returns {boolean} True for inputs, textareas, selects, and contenteditable elements
 */
export function isEditableTarget(element) {
    if (!element || typeof element.tagName !== 'string') return false;

    if (element.tagName === 'INPUT' ||
        element.tagName === 'TEXTAREA' ||
        element.tagName === 'SELECT') {
        return true;
    }

    if (element.isContentEditable) return true;

    const editable = element.closest && element.closest('[contenteditable]');
    return Boolean(editable && editable.getAttribute('contenteditable') !== 'false');
}

/**
 * Check for Ctrl or Command without Alt or Shift.
 *
 * @param {KeyboardEvent} event - Keyboard event to inspect
 * @returns {boolean} True for an unmodified primary-modifier shortcut
 */
export function hasPrimaryModifier(event) {
    return (event.ctrlKey || event.metaKey) && !event.altKey && !event.shiftKey;
}

/**
 * Check for a key pressed without Ctrl, Command, Alt, or Shift.
 *
 * @param {KeyboardEvent} event - Keyboard event to inspect
 * @param {string} key - Expected event.key value
 * @returns {boolean} True when the key matches and no modifier is held
 */
export function isUnmodifiedKey(event, key) {
    return event.key === key &&
        !event.ctrlKey &&
        !event.metaKey &&
        !event.altKey &&
        !event.shiftKey;
}

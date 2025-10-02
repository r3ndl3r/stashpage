// /js/user/account.js

/**
 * User Account Management Module
 * 
 * Handles client-side validation and user interactions for the account
 * settings page. This module provides comprehensive form validation and
 * real-time feedback for users updating their account information including:
 * - Real-time password matching validation with visual feedback
 * - Email format validation before submission
 * - Password strength requirements enforcement
 * - Current password verification for security operations
 * - Form submission validation and error prevention
 */

/**
 * Password Match Validation System
 * 
 * Provides real-time validation to ensure new password and confirm password
 * fields match during input. Updates visual feedback through border color
 * changes and custom validity messages to guide the user
 */
function initPasswordValidation() {
    const newPassword = document.getElementById('new_password');
    const confirmPassword = document.getElementById('confirm_password');
    
    if (!newPassword || !confirmPassword) {
        return; // Elements not present on this page
    }
    
    /**
     * Password Comparison Validator
     * 
     * Compares password fields and updates validation state with visual feedback
     * Sets custom validity message if passwords don't match and applies
     * appropriate CSS classes for user feedback
     */
    function validatePasswords() {
        if (confirmPassword.value && newPassword.value !== confirmPassword.value) {
            confirmPassword.setCustomValidity('Passwords do not match');
            confirmPassword.classList.add('border-red-500');
            confirmPassword.classList.remove('border-gray-600');
        } else {
            confirmPassword.setCustomValidity('');
            confirmPassword.classList.remove('border-red-500');
            confirmPassword.classList.add('border-gray-600');
        }
    }
    
    // Attach validation to input events for real-time feedback
    newPassword.addEventListener('input', validatePasswords);
    confirmPassword.addEventListener('input', validatePasswords);
}

/**
 * Form Validation Enhancement System
 * 
 * Adds comprehensive client-side validation for both email update and password
 * change forms. Validates all required fields are filled, checks email format,
 * enforces password requirements, and provides user-friendly error messages
 * before allowing form submission to the server
 */
function initFormValidation() {
    /**
     * Email Update Form Validation
     * 
     * Validates email update form to ensure new email is properly formatted
     * and current password is provided for security verification before
     * allowing submission to the server
     */
    const emailForm = document.querySelector('form[action="/user/update-email"]');
    if (emailForm) {
        emailForm.addEventListener('submit', function(event) {
            const newEmail = document.getElementById('new_email').value.trim();
            const currentPassword = document.getElementById('email_password').value;
            
            // Verify all required fields are filled
            if (!newEmail || !currentPassword) {
                event.preventDefault();
                alert('Please fill in all required fields');
                return false;
            }
            
            // Validate email format using standard regex pattern
            const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
            if (!emailRegex.test(newEmail)) {
                event.preventDefault();
                alert('Please enter a valid email address');
                return false;
            }
        });
    }
    
    /**
     * Password Update Form Validation
     * 
     * Validates password change form to ensure all password fields are filled,
     * new passwords match, and minimum length requirement is met before
     * allowing submission to prevent invalid password updates
     */
    const passwordForm = document.querySelector('form[action="/user/update-password"]');
    if (passwordForm) {
        passwordForm.addEventListener('submit', function(event) {
            const currentPassword = document.getElementById('current_password').value;
            const newPassword = document.getElementById('new_password').value;
            const confirmPassword = document.getElementById('confirm_password').value;
            
            // Verify all password fields are filled
            if (!currentPassword || !newPassword || !confirmPassword) {
                event.preventDefault();
                alert('Please fill in all password fields');
                return false;
            }
            
            // Ensure new passwords match before submission
            if (newPassword !== confirmPassword) {
                event.preventDefault();
                alert('New password and confirmation do not match');
                return false;
            }
            
            // Enforce minimum password length requirement
            if (newPassword.length < 8) {
                event.preventDefault();
                alert('New password must be at least 8 characters long');
                return false;
            }
        });
    }
}

/**
 * Application Initialization and Event Management
 * 
 * Main entry point that sets up all validation systems and event handlers
 * when the DOM is fully loaded. Initializes both password matching validation
 * and form submission validation for the account management interface
 */
document.addEventListener('DOMContentLoaded', function() {
    // Initialize real-time password matching validation
    initPasswordValidation();
    
    // Initialize comprehensive form validation
    initFormValidation();
});

/**
 * Toggle Dropdown Visibility
 * 
 * Shows or hides the settings dropdown menu when the settings button is clicked.
 * Prevents event propagation to avoid triggering the document-level close handler
 * 
 * Parameters:
 *   event : Click event object from settings button
 */
function toggleDropdown(event) {
    event.stopPropagation();
    const dropdown = document.getElementById('settings-dropdown');
    dropdown.classList.toggle('hidden');
}

/**
 * Initialize Dropdown Close Behavior
 * 
 * Sets up document-level click handler to close dropdown when clicking outside
 * of both the dropdown menu and the settings button for better UX
 */
function initDropdownCloseBehavior() {
    document.addEventListener('click', function(event) {
        const dropdown = document.getElementById('settings-dropdown');
        const button = document.getElementById('settings-button');
        
        if (!button.contains(event.target) && !dropdown.contains(event.target)) {
            dropdown.classList.add('hidden');
        }
    });
}

/**
 * Application Initialization
 * 
 * Sets up all validation and event handlers when the DOM is fully loaded
 */
document.addEventListener('DOMContentLoaded', function() {
    // Initialize real-time password matching validation
    initPasswordValidation();
    
    // Initialize comprehensive form validation
    initFormValidation();
    
    // Initialize topbar dropdown behavior
    initDropdownCloseBehavior();
});
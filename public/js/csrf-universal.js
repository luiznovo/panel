/**
 * Universal CSRF Token Handler
 * Automatically adds CSRF tokens to all forms and AJAX requests
 */

(function() {
    'use strict';
    
    // Get CSRF token from meta tag or global variable
    function getCSRFToken() {
        // Try to get from meta tag first
        const metaTag = document.querySelector('meta[name="csrf-token"]');
        if (metaTag) {
            return metaTag.getAttribute('content');
        }
        
        // Try to get from global variable
        if (typeof window.csrfToken !== 'undefined') {
            return window.csrfToken;
        }
        
        // Try to get from template variable (if available)
        if (typeof csrfToken !== 'undefined') {
            return csrfToken;
        }
        
        return null;
    }
    
    // Add CSRF token to all forms
    function addCSRFToForms() {
        const token = getCSRFToken();
        if (!token) return;
        
        const forms = document.querySelectorAll('form');
        forms.forEach(form => {
            // Skip if form already has CSRF token
            if (form.querySelector('input[name="_csrf"]')) {
                return;
            }
            
            // Skip GET forms
            if (form.method.toLowerCase() === 'get') {
                return;
            }
            
            // Add hidden CSRF input
            const csrfInput = document.createElement('input');
            csrfInput.type = 'hidden';
            csrfInput.name = '_csrf';
            csrfInput.value = token;
            form.appendChild(csrfInput);
        });
    }
    
    // Override fetch to automatically include CSRF token
    function setupFetchCSRF() {
        const token = getCSRFToken();
        if (!token) return;
        
        const originalFetch = window.fetch;
        window.fetch = function(url, options = {}) {
            // Only add CSRF for POST, PUT, PATCH, DELETE requests
            const method = (options.method || 'GET').toUpperCase();
            if (['POST', 'PUT', 'PATCH', 'DELETE'].includes(method)) {
                options.headers = options.headers || {};
                
                // Add CSRF token if not already present
                if (!options.headers['X-CSRF-Token'] && !options.headers['x-csrf-token']) {
                    options.headers['X-CSRF-Token'] = token;
                }
            }
            
            return originalFetch.call(this, url, options);
        };
    }
    
    // Override XMLHttpRequest to automatically include CSRF token
    function setupXHRCSRF() {
        const token = getCSRFToken();
        if (!token) return;
        
        const originalOpen = XMLHttpRequest.prototype.open;
        const originalSend = XMLHttpRequest.prototype.send;
        
        XMLHttpRequest.prototype.open = function(method, url, async, user, password) {
            this._method = method.toUpperCase();
            return originalOpen.call(this, method, url, async, user, password);
        };
        
        XMLHttpRequest.prototype.send = function(data) {
            // Add CSRF token for POST, PUT, PATCH, DELETE requests
            if (['POST', 'PUT', 'PATCH', 'DELETE'].includes(this._method)) {
                // Check if CSRF token is not already set
                if (!this.getRequestHeader('X-CSRF-Token') && !this.getRequestHeader('x-csrf-token')) {
                    this.setRequestHeader('X-CSRF-Token', token);
                }
            }
            
            return originalSend.call(this, data);
        };
    }
    
    // Handle dynamic forms (for SPAs or dynamically created content)
    function observeNewForms() {
        if (typeof MutationObserver === 'undefined') return;
        
        const observer = new MutationObserver(function(mutations) {
            mutations.forEach(function(mutation) {
                mutation.addedNodes.forEach(function(node) {
                    if (node.nodeType === Node.ELEMENT_NODE) {
                        // Check if the added node is a form
                        if (node.tagName === 'FORM') {
                            addCSRFToSingleForm(node);
                        }
                        // Check for forms within the added node
                        const forms = node.querySelectorAll ? node.querySelectorAll('form') : [];
                        forms.forEach(addCSRFToSingleForm);
                    }
                });
            });
        });
        
        observer.observe(document.body, {
            childList: true,
            subtree: true
        });
    }
    
    function addCSRFToSingleForm(form) {
        const token = getCSRFToken();
        if (!token || form.querySelector('input[name="_csrf"]') || form.method.toLowerCase() === 'get') {
            return;
        }
        
        const csrfInput = document.createElement('input');
        csrfInput.type = 'hidden';
        csrfInput.name = '_csrf';
        csrfInput.value = token;
        form.appendChild(csrfInput);
    }
    
    // Initialize when DOM is ready
    function init() {
        addCSRFToForms();
        setupFetchCSRF();
        setupXHRCSRF();
        observeNewForms();
    }
    
    // Run initialization
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
    
    // Expose function for manual use
    window.addCSRFToForms = addCSRFToForms;
    
})();
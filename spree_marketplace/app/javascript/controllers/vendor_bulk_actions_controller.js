import { Controller } from '@hotwired/stimulus'

// Bulk actions controller for vendor management
// Follows Spree admin patterns for bulk operations
export default class extends Controller {
  static targets = ['checkbox', 'selectAll', 'bulkActions', 'selectedCount']
  static values = { 
    confirmMessage: String,
    selectedCountText: String
  }
  
  connect() {
    this.updateBulkActions()
  }
  
  // Toggle all checkboxes when select all is clicked
  toggleAll(event) {
    const isChecked = event.target.checked
    
    this.checkboxTargets.forEach(checkbox => {
      checkbox.checked = isChecked
      this.toggleRowHighlight(checkbox)
    })
    
    this.updateBulkActions()
  }
  
  // Update select all state when individual checkbox changes
  updateSelectAll() {
    const checkedCount = this.getCheckedCount()
    const totalCount = this.checkboxTargets.length
    
    if (this.hasSelectAllTarget) {
      if (checkedCount === 0) {
        this.selectAllTarget.checked = false
        this.selectAllTarget.indeterminate = false
      } else if (checkedCount === totalCount) {
        this.selectAllTarget.checked = true
        this.selectAllTarget.indeterminate = false
      } else {
        this.selectAllTarget.checked = false
        this.selectAllTarget.indeterminate = true
      }
    }
    
    this.updateBulkActions()
  }
  
  // Toggle row highlighting for selected items
  toggleRowHighlight(checkbox) {
    const row = checkbox.closest('tr')
    if (row) {
      if (checkbox.checked) {
        row.classList.add('table-active')
      } else {
        row.classList.remove('table-active')
      }
    }
  }
  
  // Handle individual checkbox changes
  checkboxChanged(event) {
    this.toggleRowHighlight(event.target)
    this.updateSelectAll()
  }
  
  // Update bulk actions visibility and count
  updateBulkActions() {
    const checkedCount = this.getCheckedCount()
    
    if (this.hasBulkActionsTarget) {
      if (checkedCount > 0) {
        this.bulkActionsTarget.style.display = 'block'
      } else {
        this.bulkActionsTarget.style.display = 'none'
      }
    }
    
    if (this.hasSelectedCountTarget) {
      const text = this.selectedCountTextValue.replace('%{count}', checkedCount)
      this.selectedCountTarget.textContent = text
    }
  }
  
  // Execute bulk action with confirmation
  executeBulkAction(event) {
    event.preventDefault()
    
    const checkedCount = this.getCheckedCount()
    if (checkedCount === 0) {
      return false
    }
    
    const action = event.currentTarget.dataset.action
    const confirmMessage = this.confirmMessageValue
                               .replace('%{count}', checkedCount)
                               .replace('%{action}', action)
    
    if (confirm(confirmMessage)) {
      // Get selected vendor IDs
      const selectedIds = this.getSelectedIds()
      
      // Create form data
      const form = document.createElement('form')
      form.method = 'POST'
      form.action = event.currentTarget.href
      
      // Add CSRF token
      const csrfToken = document.querySelector('meta[name="csrf-token"]')
      if (csrfToken) {
        const csrfInput = document.createElement('input')
        csrfInput.type = 'hidden'
        csrfInput.name = 'authenticity_token'
        csrfInput.value = csrfToken.content
        form.appendChild(csrfInput)
      }
      
      // Add selected IDs
      selectedIds.forEach(id => {
        const input = document.createElement('input')
        input.type = 'hidden'
        input.name = 'vendor_ids[]'
        input.value = id
        form.appendChild(input)
      })
      
      // Submit form
      document.body.appendChild(form)
      form.submit()
    }
    
    return false
  }
  
  // Get count of checked items
  getCheckedCount() {
    return this.checkboxTargets.filter(cb => cb.checked).length
  }
  
  // Get IDs of selected items
  getSelectedIds() {
    return this.checkboxTargets
               .filter(cb => cb.checked)
               .map(cb => cb.value)
  }
  
  // Clear all selections
  clearSelection() {
    this.checkboxTargets.forEach(checkbox => {
      checkbox.checked = false
      this.toggleRowHighlight(checkbox)
    })
    
    if (this.hasSelectAllTarget) {
      this.selectAllTarget.checked = false
      this.selectAllTarget.indeterminate = false
    }
    
    this.updateBulkActions()
  }
}
import { Controller } from '@hotwired/stimulus'

// Vendor form controller for enhanced form interactions
// Handles dynamic form fields and validation
export default class extends Controller {
  static targets = [
    'businessType', 'taxIdField', 'licenseField', 'commissionRate', 
    'commissionDisplay', 'logoPreview', 'logoInput', 'categoryInput', 'tagInput'
  ]
  static values = {
    defaultCommissionRate: Number,
    maxFileSize: Number
  }
  
  connect() {
    this.updateCommissionDisplay()
    this.setupTagInputs()
  }
  
  // Handle business type changes
  businessTypeChanged() {
    const businessType = this.businessTypeTarget.value
    
    // Show/hide relevant fields based on business type
    this.updateFieldVisibility(businessType)
    
    // Update validation requirements
    this.updateValidationRequirements(businessType)
  }
  
  // Update field visibility based on business type
  updateFieldVisibility(businessType) {
    const corporateTypes = ['corporation', 's_corporation', 'llc']
    const individualTypes = ['individual', 'sole_proprietorship']
    
    if (this.hasLicenseFieldTarget) {
      if (corporateTypes.includes(businessType)) {
        this.licenseFieldTarget.style.display = 'block'
        this.licenseFieldTarget.querySelector('input').required = true
      } else {
        this.licenseFieldTarget.style.display = 'none'
        this.licenseFieldTarget.querySelector('input').required = false
      }
    }
  }
  
  // Update validation requirements
  updateValidationRequirements(businessType) {
    if (this.hasTaxIdFieldTarget) {
      const taxIdInput = this.taxIdFieldTarget.querySelector('input')
      const corporateTypes = ['corporation', 's_corporation', 'llc']
      
      if (corporateTypes.includes(businessType)) {
        taxIdInput.placeholder = 'EIN (XX-XXXXXXX)'
        taxIdInput.pattern = '\\d{2}-\\d{7}'
      } else {
        taxIdInput.placeholder = 'SSN or EIN'
        taxIdInput.pattern = null
      }
    }
  }
  
  // Handle commission rate changes
  commissionRateChanged() {
    this.updateCommissionDisplay()
    this.validateCommissionRate()
  }
  
  // Update commission rate display
  updateCommissionDisplay() {
    if (this.hasCommissionRateTarget && this.hasCommissionDisplayTarget) {
      const rate = parseFloat(this.commissionRateTarget.value) || 0
      const percentage = (rate * 100).toFixed(1)
      this.commissionDisplayTarget.textContent = `${percentage}%`
      
      // Update color based on rate
      if (rate >= 0.25) {
        this.commissionDisplayTarget.className = 'text-warning'
      } else if (rate >= 0.15) {
        this.commissionDisplayTarget.className = 'text-primary'
      } else {
        this.commissionDisplayTarget.className = 'text-success'
      }
    }
  }
  
  // Validate commission rate
  validateCommissionRate() {
    if (this.hasCommissionRateTarget) {
      const rate = parseFloat(this.commissionRateTarget.value)
      const input = this.commissionRateTarget
      
      // Remove previous validation classes
      input.classList.remove('is-valid', 'is-invalid')
      
      if (rate < 0.05) {
        input.classList.add('is-invalid')
        this.setValidationMessage(input, 'Commission rate must be at least 5%')
      } else if (rate > 0.50) {
        input.classList.add('is-invalid')
        this.setValidationMessage(input, 'Commission rate cannot exceed 50%')
      } else {
        input.classList.add('is-valid')
        this.clearValidationMessage(input)
      }
    }
  }
  
  // Handle logo file selection
  logoSelected(event) {
    const file = event.target.files[0]
    
    if (file) {
      // Validate file size
      if (file.size > this.maxFileSizeValue) {
        this.showFileError('File size exceeds maximum allowed size')
        event.target.value = ''
        return
      }
      
      // Validate file type
      if (!file.type.startsWith('image/')) {
        this.showFileError('Please select an image file')
        event.target.value = ''
        return
      }
      
      // Show preview
      this.showLogoPreview(file)
    }
  }
  
  // Show logo preview
  showLogoPreview(file) {
    if (this.hasLogoPreviewTarget) {
      const reader = new FileReader()
      
      reader.onload = (e) => {
        this.logoPreviewTarget.innerHTML = `
          <img src="${e.target.result}" 
               class="img-thumbnail" 
               style="max-width: 200px; max-height: 150px;"
               alt="Logo preview">
          <div class="mt-2">
            <button type="button" 
                    class="btn btn-sm btn-outline-danger"
                    data-action="click->vendor-form#removeLogo">
              Remove Logo
            </button>
          </div>
        `
      }
      
      reader.readAsDataURL(file)
    }
  }
  
  // Remove logo
  removeLogo() {
    if (this.hasLogoInputTarget) {
      this.logoInputTarget.value = ''
    }
    
    if (this.hasLogoPreviewTarget) {
      this.logoPreviewTarget.innerHTML = ''
    }
  }
  
  // Setup tag inputs with autocomplete
  setupTagInputs() {
    [this.categoryInputTarget, this.tagInputTarget].forEach(input => {
      if (input) {
        this.initializeTagInput(input)
      }
    })
  }
  
  // Initialize tag input with autocomplete
  initializeTagInput(input) {
    // Simple tag input functionality
    input.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ',') {
        event.preventDefault()
        this.addTag(input, input.value.trim())
        input.value = ''
      }
    })
    
    input.addEventListener('blur', () => {
      if (input.value.trim()) {
        this.addTag(input, input.value.trim())
        input.value = ''
      }
    })
  }
  
  // Add tag to input
  addTag(input, tagName) {
    if (!tagName) return
    
    const currentTags = input.value ? input.value.split(',').map(t => t.trim()) : []
    
    if (!currentTags.includes(tagName)) {
      currentTags.push(tagName)
      input.value = currentTags.join(', ')
    }
  }
  
  // Utility methods
  setValidationMessage(input, message) {
    let feedback = input.parentNode.querySelector('.invalid-feedback')
    
    if (!feedback) {
      feedback = document.createElement('div')
      feedback.className = 'invalid-feedback'
      input.parentNode.appendChild(feedback)
    }
    
    feedback.textContent = message
  }
  
  clearValidationMessage(input) {
    const feedback = input.parentNode.querySelector('.invalid-feedback')
    if (feedback) {
      feedback.remove()
    }
  }
  
  showFileError(message) {
    // Create temporary error message
    const errorDiv = document.createElement('div')
    errorDiv.className = 'alert alert-danger alert-dismissible fade show mt-2'
    errorDiv.innerHTML = `
      ${message}
      <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    `
    
    if (this.hasLogoInputTarget) {
      this.logoInputTarget.parentNode.appendChild(errorDiv)
      
      // Auto-remove after 5 seconds
      setTimeout(() => {
        if (errorDiv.parentNode) {
          errorDiv.remove()
        }
      }, 5000)
    }
  }
}
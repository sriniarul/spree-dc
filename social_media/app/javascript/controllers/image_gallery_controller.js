import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "gallery",
    "additionalGallery",
    "selectedGallery",
    "selectedPreview",
    "selectionCount",
    "productInfo",
    "proceedButton"
  ]

  connect() {
    this.selectedImages = []
    this.additionalImages = []
    this.productData = {}
    this.maxImages = 10

    // Initialize drag and drop for the gallery
    this.initializeDragAndDrop()
  }

  openModal(event) {
    const button = event.currentTarget

    // Get product data from button
    this.productData = {
      id: button.dataset.productId,
      name: button.dataset.productName,
      price: button.dataset.productPrice,
      images: JSON.parse(button.dataset.productImages || '[]')
    }

    // Update product info display
    this.productInfoTarget.textContent = `${this.productData.name} - ${this.productData.price}`

    // Reset selections
    this.selectedImages = []
    this.additionalImages = []

    // Render product images
    this.renderProductImages()

    // Clear additional images
    this.additionalGalleryTarget.innerHTML = ''

    // Update UI
    this.updateUI()
  }

  renderProductImages() {
    this.galleryTarget.innerHTML = ''

    this.productData.images.forEach((image, index) => {
      const col = document.createElement('div')
      col.className = 'col-md-3 col-sm-4 col-6'
      col.innerHTML = `
        <div class="image-gallery-item border rounded p-2" data-image-id="${image.id}" data-image-type="product">
          <input type="checkbox"
                 class="form-check-input selection-checkbox"
                 data-action="change->image-gallery#toggleSelection"
                 data-image-id="${image.id}"
                 data-image-index="${index}">
          <div class="selection-order"></div>
          <img src="${image.thumb_url}" alt="Product image ${index + 1}" loading="lazy">
          <div class="text-center mt-2 small text-muted">Image ${index + 1}</div>
        </div>
      `
      this.galleryTarget.appendChild(col)
    })
  }

  toggleSelection(event) {
    const checkbox = event.target
    const imageId = checkbox.dataset.imageId
    const imageIndex = parseInt(checkbox.dataset.imageIndex)
    const imageItem = checkbox.closest('.image-gallery-item')
    const imageType = imageItem.dataset.imageType

    if (checkbox.checked) {
      // Add to selection if under max limit
      if (this.selectedImages.length < this.maxImages) {
        const imageData = imageType === 'product'
          ? this.productData.images[imageIndex]
          : this.additionalImages.find(img => img.tempId === imageId)

        this.selectedImages.push({
          id: imageId,
          type: imageType,
          data: imageData
        })
        imageItem.classList.add('selected')
      } else {
        checkbox.checked = false
        alert(`You can select up to ${this.maxImages} images only`)
      }
    } else {
      // Remove from selection
      this.selectedImages = this.selectedImages.filter(img => img.id !== imageId)
      imageItem.classList.remove('selected')
    }

    this.updateUI()
  }

  selectAll() {
    const checkboxes = this.galleryTarget.querySelectorAll('.selection-checkbox')
    const availableSlots = this.maxImages - this.selectedImages.length

    let count = 0
    checkboxes.forEach(checkbox => {
      if (!checkbox.checked && count < availableSlots) {
        checkbox.checked = true
        checkbox.dispatchEvent(new Event('change', { bubbles: true }))
        count++
      }
    })
  }

  deselectAll() {
    const checkboxes = this.element.querySelectorAll('.selection-checkbox:checked')
    checkboxes.forEach(checkbox => {
      checkbox.checked = false
      checkbox.dispatchEvent(new Event('change', { bubbles: true }))
    })
  }

  handleAdditionalImages(event) {
    const files = Array.from(event.target.files)

    if (this.selectedImages.length + files.length > this.maxImages) {
      alert(`You can only add ${this.maxImages - this.selectedImages.length} more image(s)`)
      return
    }

    files.forEach((file, index) => {
      // Validate file
      if (!file.type.startsWith('image/')) {
        alert(`${file.name} is not an image file`)
        return
      }

      if (file.size > 8 * 1024 * 1024) {
        alert(`${file.name} is too large. Max size is 8MB`)
        return
      }

      // Create temporary ID
      const tempId = `additional-${Date.now()}-${index}`

      // Read file and create preview
      const reader = new FileReader()
      reader.onload = (e) => {
        const imageData = {
          tempId: tempId,
          file: file,
          url: e.target.result,
          thumb_url: e.target.result,
          blob_signed_id: null // Will be uploaded separately
        }

        this.additionalImages.push(imageData)
        this.renderAdditionalImage(imageData)
      }
      reader.readAsDataURL(file)
    })

    // Clear input
    event.target.value = ''
  }

  renderAdditionalImage(imageData) {
    const col = document.createElement('div')
    col.className = 'col-md-3 col-sm-4 col-6'
    col.dataset.imageId = imageData.tempId

    col.innerHTML = `
      <div class="image-gallery-item border rounded p-2" data-image-id="${imageData.tempId}" data-image-type="additional">
        <input type="checkbox"
               class="form-check-input selection-checkbox"
               data-action="change->image-gallery#toggleSelection"
               data-image-id="${imageData.tempId}"
               data-image-index="${this.additionalImages.length - 1}">
        <div class="selection-order"></div>
        <div class="remove-icon" data-action="click->image-gallery#removeAdditionalImage" data-image-id="${imageData.tempId}">
          <i class="fa fa-times"></i>
        </div>
        <img src="${imageData.thumb_url}" alt="Additional image" loading="lazy">
        <div class="text-center mt-2 small text-muted">Additional</div>
      </div>
    `

    this.additionalGalleryTarget.appendChild(col)
  }

  removeAdditionalImage(event) {
    const imageId = event.currentTarget.dataset.imageId

    // Remove from additional images
    this.additionalImages = this.additionalImages.filter(img => img.tempId !== imageId)

    // Remove from selected images
    this.selectedImages = this.selectedImages.filter(img => img.id !== imageId)

    // Remove from DOM
    const col = this.additionalGalleryTarget.querySelector(`[data-image-id="${imageId}"]`)
    if (col) col.remove()

    this.updateUI()
  }

  updateUI() {
    // Update selection count
    this.selectionCountTarget.textContent = `${this.selectedImages.length} image${this.selectedImages.length !== 1 ? 's' : ''} selected`

    // Update selection order badges
    this.element.querySelectorAll('.image-gallery-item.selected').forEach(item => {
      const imageId = item.dataset.imageId
      const index = this.selectedImages.findIndex(img => img.id === imageId)
      const orderBadge = item.querySelector('.selection-order')
      if (orderBadge && index !== -1) {
        orderBadge.textContent = index + 1
      }
    })

    // Show/hide selected preview section
    if (this.selectedImages.length > 0) {
      this.selectedPreviewTarget.style.display = 'block'
      this.renderSelectedImages()
    } else {
      this.selectedPreviewTarget.style.display = 'none'
    }

    // Enable/disable proceed button
    this.proceedButtonTarget.disabled = this.selectedImages.length === 0
  }

  renderSelectedImages() {
    this.selectedGalleryTarget.innerHTML = ''

    this.selectedImages.forEach((selectedImage, index) => {
      const imageData = selectedImage.data
      const col = document.createElement('div')
      col.className = 'col-md-2 col-sm-3 col-4'
      col.dataset.selectedIndex = index
      col.draggable = true
      col.innerHTML = `
        <div class="image-gallery-item border rounded p-2 selected">
          <div class="selection-order">${index + 1}</div>
          <img src="${imageData.thumb_url}" alt="Selected image ${index + 1}" loading="lazy">
        </div>
      `
      this.selectedGalleryTarget.appendChild(col)
    })
  }

  initializeDragAndDrop() {
    let draggedElement = null
    let draggedIndex = null

    // Use event delegation for drag events
    this.element.addEventListener('dragstart', (e) => {
      if (e.target.closest('#selected-images-gallery [data-selected-index]')) {
        draggedElement = e.target.closest('[data-selected-index]')
        draggedIndex = parseInt(draggedElement.dataset.selectedIndex)
        draggedElement.classList.add('dragging')
      }
    })

    this.element.addEventListener('dragend', (e) => {
      if (draggedElement) {
        draggedElement.classList.remove('dragging')
        draggedElement = null
        draggedIndex = null
      }
    })

    this.element.addEventListener('dragover', (e) => {
      e.preventDefault()
      const targetElement = e.target.closest('#selected-images-gallery [data-selected-index]')
      if (targetElement && draggedElement && targetElement !== draggedElement) {
        const targetIndex = parseInt(targetElement.dataset.selectedIndex)

        // Reorder in array
        const [movedItem] = this.selectedImages.splice(draggedIndex, 1)
        this.selectedImages.splice(targetIndex, 0, movedItem)

        // Update dragged index for continuous dragging
        draggedIndex = targetIndex

        // Re-render
        this.updateUI()
      }
    })
  }

  proceedToPost() {
    if (this.selectedImages.length === 0) {
      alert('Please select at least one image')
      return
    }

    // Prepare data to pass to the form
    const selectedImageIds = this.selectedImages.map(img => ({
      id: img.id,
      type: img.type,
      url: img.data.url,
      blob_signed_id: img.data.blob_signed_id
    }))

    // Store in sessionStorage to pass to next page
    sessionStorage.setItem('selectedImages', JSON.stringify(selectedImageIds))
    sessionStorage.setItem('additionalImageFiles', JSON.stringify(
      this.additionalImages.map(img => ({
        tempId: img.tempId,
        fileName: img.file.name
      }))
    ))

    // Store File objects separately (can't stringify File objects)
    this.additionalImageFiles = this.additionalImages.map(img => img.file)
    window.additionalImageFiles = this.additionalImageFiles

    // Close modal
    const modal = bootstrap.Modal.getInstance(this.element.querySelector('.modal'))
    if (modal) modal.hide()

    // Navigate to post form
    window.location.href = `/admin/products/${this.productData.id}/social_media/post`
  }
}

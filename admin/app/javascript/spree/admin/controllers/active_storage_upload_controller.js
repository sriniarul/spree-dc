import { Controller } from '@hotwired/stimulus'

import Uppy from '@uppy/core'
import Dashboard from '@uppy/dashboard'
import ImageEditor from '@uppy/image-editor'
import ActiveStorageUpload from 'spree/admin/helpers/uppy_active_storage'

export default class extends Controller {
  static targets = ['thumb', 'toolbar', 'remove', 'placeholder']

  static values = {
    fieldName: String,
    thumbWidth: Number,
    thumbHeight: Number,
    autoSubmit: Boolean,
    multiple: { type: Boolean, default: false },
    crop: { type: Boolean, default: false },
    allowedFileTypes: { type: Array, default: [] },
    closeAfterFinish: { type: Boolean, default: true },
    inline: { type: Boolean, default: false },
    height: Number,
    hideCancelButton: { type: Boolean, default: false },
    disableThumbnailGenerator: { type: Boolean, default: false },
    maxFileSize: { type: Number, default: 5242880 }, // 5MB default
    compressionQuality: { type: Number, default: 0.8 },
    maxWidth: { type: Number, default: 2048 },
    maxHeight: { type: Number, default: 2048 },
    compressOnClient: { type: Boolean, default: true }
  }

  connect() {
    this.uppy = new Uppy({
      autoProceed: true,
      allowMultipleUploads: false,
      restrictions: {
        allowedFileTypes: this.allowedFileTypesValue.length ? this.allowedFileTypesValue : undefined
      },
      debug: true
    })

    this.uppy.use(ActiveStorageUpload, {
      directUploadUrl: document.querySelector("meta[name='direct-upload-url']").getAttribute('content'),
      crop: this.cropValue
    })

    let dashboardOptions = {
      closeAfterFinish: this.closeAfterFinishValue
    }
    if (this.cropValue == true) {
      dashboardOptions = {
        autoOpen: 'imageEditor',
        closeAfterFinish: false
      }
    }

    if (this.inlineValue == true) {
      dashboardOptions.inline = true
      dashboardOptions.closeAfterFinish = false
      dashboardOptions.target = this.element
      if (this.heightValue) {
        dashboardOptions.height = this.heightValue
      }
      dashboardOptions.doneButtonHandler = null
    }

    dashboardOptions.hideCancelButton = this.hideCancelButtonValue
    dashboardOptions.disableThumbnailGenerator = this.disableThumbnailGeneratorValue

    this.uppy.use(Dashboard, dashboardOptions)

    if (this.cropValue == true) {
      this.uppy.use(ImageEditor, {
        cropperOptions: {
          aspectRatio: this.thumbWidthValue / this.thumbHeightValue
        }
      })
    }

    // Add preprocessing for compression
    console.log('🚀 Controller loaded! Compression config:', {
      compressOnClient: this.compressOnClientValue,
      maxFileSize: this.maxFileSizeValue,
      quality: this.compressionQualityValue
    })

    // Use file-added event instead of preprocessor
    this.uppy.on('file-added', async (file) => {
      console.log('🔥 File added:', file.name, 'Size:', file.size)

      if (this.compressOnClientValue && this.needsCompression(file)) {
        console.log('🗜️ Starting compression for:', file.name)
        await this.compressFile(file)
      } else {
        console.log('⏭️ No compression needed for:', file.name)
      }
    })

    this.uppy.on('file-editor:complete', (updatedFile) => {
      console.log('File editing complete:', updatedFile)

      this.handleUI(updatedFile)
      this.uppy.getPlugin('Dashboard').closeModal()
    })

    this.uppy.on('upload-success', (file, response) => {
      this.handleUI(file, response)
    })

    this.uppy.on('dashboard:modal-closed', () => {
      this.uppy.clear()
    })
  }

  open(event) {
    event.preventDefault()
    this.uppy.getPlugin('Dashboard').openModal()
  }

  remove(event) {
    event.preventDefault()

    if (window.confirm('Are you sure?')) {
      if (this.hasThumbTarget) {
        // handle thumb preview
        this.thumbTarget.style = 'display: none !important'
        this.thumbTarget.dataset.imageSignedId = null
        this.thumbTarget.src = ''
      }

      // hide toolbar if attached
      if (this.hasToolbarTarget) {
        this.toolbarTarget.style = 'display: none !important'
      }

      // mark for removal (on the backend)
      if (this.hasRemoveTarget) {
        this.removeTarget.value = '1'
      }

      if (this.hasPlaceholderTarget) {
        this.placeholderTarget.style.display = null
      }

      if (this.autoSubmitValue == true) {
        this.element.closest('form').requestSubmit()
      }

      this.uppy.clear()
    }
  }

  handleUI(file, response = null) {
    if (this.hasPlaceholderTarget) {
      this.placeholderTarget.style = 'display: none !important'
    }

    if (this.hasToolbarTarget) {
      this.toolbarTarget.style = 'display: none !important'
    }

    const signedId = response?.signed_id || file.response?.signed_id

    if (signedId?.length) {
      if (this.hasThumbTarget) {
        this.thumbTarget.src = URL.createObjectURL(file.data)
        this.thumbTarget.style.display = null
        this.thumbTarget.dataset.imageSignedId = signedId
        this.thumbTarget.width = this.thumbWidthValue
        this.thumbTarget.height = this.thumbHeightValue
      }

      // Remove existing hidden field for this file, if any
      const existingField = this.element.querySelector(`input[name="${this.fieldNameValue}"]`)
      if (existingField) {
        existingField.remove()
      }

      const hiddenField = document.createElement('input')

      hiddenField.setAttribute('type', 'hidden')
      hiddenField.setAttribute('value', signedId)

      if (this.multipleValue) {
        hiddenField.setAttribute('name', `${this.fieldNameValue}[]`)
      } else {
        hiddenField.setAttribute('name', this.fieldNameValue)
      }

      this.element.appendChild(hiddenField)

      // Propagate a custom 'active-storage-upload:success' event when upload completes and field updated
      const event = new CustomEvent('active-storage-upload:success', {
        detail: {
          file: file,
          signedId: signedId,
          controller: this
        },
        bubbles: true
      })
      this.element.dispatchEvent(event)
    }

    // show toolbar if attached
    if (this.hasToolbarTarget) {
      this.toolbarTarget.style.display = null
    }

    if (this.hasRemoveTarget) {
      this.removeTarget.value = null
    }

    if (this.autoSubmitValue == true) {
      this.element.closest('form').requestSubmit()
    }
  }


  needsCompression(file) {
    return file.size > this.maxFileSizeValue && file.type.startsWith('image/')
  }

  async compressFile(file) {
    try {
      const canvas = document.createElement('canvas')
      const ctx = canvas.getContext('2d')
      const img = new Image()

      return new Promise((resolve, reject) => {
        img.onload = () => {
          // Calculate new dimensions
          let { width, height } = this.calculateDimensions(img.width, img.height)

          canvas.width = width
          canvas.height = height

          // Draw and compress
          ctx.drawImage(img, 0, 0, width, height)

          canvas.toBlob((compressedBlob) => {
            if (compressedBlob && compressedBlob.size < file.size) {
              console.log(`Compressed ${file.name} from ${file.size} to ${compressedBlob.size} bytes`)

              // Update the file in uppy with compressed data
              this.uppy.setFileState(file.id, {
                size: compressedBlob.size,
                data: compressedBlob
              })
            }
            resolve()
          }, file.type, this.compressionQualityValue)
        }

        img.onerror = () => reject(new Error('Failed to load image'))
        img.src = URL.createObjectURL(file.data)
      })
    } catch (error) {
      console.warn('Image compression failed:', error)
    }
  }

  calculateDimensions(originalWidth, originalHeight) {
    if (originalWidth <= this.maxWidthValue && originalHeight <= this.maxHeightValue) {
      return { width: originalWidth, height: originalHeight }
    }

    const widthRatio = this.maxWidthValue / originalWidth
    const heightRatio = this.maxHeightValue / originalHeight
    const ratio = Math.min(widthRatio, heightRatio)

    return {
      width: Math.round(originalWidth * ratio),
      height: Math.round(originalHeight * ratio)
    }
  }
}

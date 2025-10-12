import { Controller } from '@hotwired/stimulus'
import { post } from '@rails/request.js'
import Uppy from '@uppy/core'
import Dashboard from '@uppy/dashboard'
import ActiveStorageUpload from 'spree/admin/helpers/uppy_active_storage'

export default class extends Controller {
  static values = {
    assetClass: { type: String, default: 'Spree::Image' },
    viewableId: String,
    viewableType: String,
    multiple: { type: Boolean, default: false },
    type: { type: String, default: 'image' },
    allowedFileTypes: { type: Array, default: [] },
    adminAssetsPath: String,
    maxFileSize: { type: Number, default: 512000 },
    compressionQuality: { type: Number, default: 0.8 },
    maxWidth: { type: Number, default: 2048 },
    maxHeight: { type: Number, default: 2048 },
    compressOnClient: { type: Boolean, default: true }
  }

  connect() {
    console.log('🚀 Asset uploader loaded! Compression config:', {
      compressOnClient: this.compressOnClientValue,
      maxFileSize: this.maxFileSizeValue,
      quality: this.compressionQualityValue
    })

    this.uppy = new Uppy({
      autoProceed: false, // Disable auto upload to control timing
      allowMultipleUploads: this.multipleValue,
      debug: true,
      restrictions: {
        allowedFileTypes: this.allowedFileTypesValue.length ? this.allowedFileTypesValue : undefined
      }
    })

    this.uppy.use(ActiveStorageUpload, {
      directUploadUrl: document.querySelector("meta[name='direct-upload-url']").getAttribute('content')
    })

    this.uppy.use(Dashboard, {
      closeAfterFinish: true
    })

    // Add compression
    this.uppy.on('file-added', async (file) => {
      console.log('🔥 File added:', file.name, 'Size:', file.size)

      if (this.compressOnClientValue && this.needsCompression(file)) {
        console.log('🗜️ Starting compression for:', file.name)
        await this.compressFile(file)
      } else {
        console.log('⏭️ No compression needed for:', file.name)
      }

      // Start upload after compression is complete
      console.log('🚀 Starting upload...')
      this.uppy.upload()
    })

    this.uppy.on('upload-success', (file, response) => {
      this.handleSuccessResult(response)
    })
  }

  open(event) {
    event.preventDefault()
    this.uppy.getPlugin('Dashboard').openModal()
  }

  handleSuccessResult(response) {
    post(this.adminAssetsPathValue, {
      body: JSON.stringify({
        asset: {
          type: this.assetClassValue,
          viewable_type: this.viewableTypeValue,
          viewable_id: this.viewableIdValue,
          attachment: response.signed_id
        }
      }),
      responseKind: 'turbo-stream'
    })
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
              console.log(`🗜️ Compressed ${file.name} from ${file.size} to ${compressedBlob.size} bytes`)

              // Update the file in uppy with compressed data
              this.uppy.setFileState(file.id, {
                size: compressedBlob.size,
                data: compressedBlob,
                name: file.name,
                type: file.type
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

// Social Media JavaScript - Image Gallery Controller
import ImageGalleryController from "controllers/image_gallery_controller"

// Get or create existing Stimulus application
const application = window.Stimulus

// Register the image gallery controller if application exists
if (application) {
  application.register("image-gallery", ImageGalleryController)
}

export { ImageGalleryController }

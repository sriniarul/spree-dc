// Import and register all Stimulus controllers
import { application } from "@hotwired/stimulus"
import ImageGalleryController from "./image_gallery_controller"

application.register("image-gallery", ImageGalleryController)
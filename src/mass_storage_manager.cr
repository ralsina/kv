# Mass Storage Manager for KVM system (new model)
class MassStorageManager
  Log = ::Log.for(self)

  @selected_image : String? = nil

  # List available disk images in ./disk-images
  def available_images
    Dir.glob("./disk-images/*").select { |fname| File.file?(fname) }
  end

  # Attach a disk image as the USB mass storage device
  def select_image(image_path : String?)
    if image_path && !File.exists?(image_path)
      return {success: false, message: "Image does not exist"}
    end
    @selected_image = image_path
    Log.info { image_path ? "Selected disk image: #{image_path}" : "Detached disk image" }
    {success: true, selected: @selected_image}
  end

  # Return the currently selected image
  def selected_image
    @selected_image
  end

  # Status for API
  def status
    {
      selected_image:   @selected_image,
      available_images: available_images,
    }
  end

  def cleanup
    @selected_image = nil
  end
end

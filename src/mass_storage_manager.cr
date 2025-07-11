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
    Log.info { "select_image called with: #{image_path.inspect}" }
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

  # Returns a hash with the actual mass storage status from the system, not just internal state
  def actual_status
    base = "/sys/kernel/config/usb_gadget/odroidc2_composite/functions/mass_storage.0"
    exists = Dir.exists?(base)
    file = nil
    ro = nil
    attached = false
    if exists
      file_file = File.join(base, "lun.0/file")
      ro_file = File.join(base, "lun.0/ro")
      if File.exists?(file_file)
        file = File.read(file_file).strip
        attached = !file.empty?
      end
      if File.exists?(ro_file)
        ro = File.read(ro_file).strip == "1"
      end
    end
    {
      exists:         exists,
      attached:       attached,
      file:           file,
      ro:             ro,
      configured:     !@selected_image.nil?,
      selected_image: @selected_image,
    }
  end

  def cleanup
    @selected_image = nil
  end
end

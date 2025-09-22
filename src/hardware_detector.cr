require "log"

module HardwareDetector
  Log = ::Log.for("hardware_detector")

  # Check if USB OTG hardware is available
  def self.otg_hardware_available? : Bool
    # Check if USB gadget configfs is available
    unless Dir.exists?("/sys/kernel/config/usb_gadget")
      Log.warn { "USB gadget configfs not available" }
      return false
    end

    # Check if libcomposite module is loaded or can be loaded
    begin
      lsmod_output = `lsmod | grep libcomposite 2>/dev/null`
      if lsmod_output.strip.empty?
        Log.debug { "libcomposite module not detected, attempting to load it..." }
        result = `modprobe libcomposite 2>&1`
        unless $?.success?
          Log.warn { "Failed to load libcomposite module: #{result}" }
          return false
        end
        Log.debug { "libcomposite module loaded successfully" }
      else
        Log.debug { "libcomposite module is already loaded" }
      end
    rescue ex
      Log.warn { "Could not check/load libcomposite module: #{ex.message}" }
      return false
    end

    # Check for typical OTG controllers (USB device controllers)
    found_controller = false

    # First check /sys/class/udc - it should contain entries for USB device controllers
    if Dir.exists?("/sys/class/udc")
      udc_entries = Dir.children("/sys/class/udc")
      unless udc_entries.empty?
        Log.debug { "Found UDC entries: #{udc_entries.join(", ")}" }
        found_controller = true
      end
    end

    # If no UDC entries, check for platform devices that might support OTG
    unless found_controller
      controllers = [
        "/sys/bus/platform/devices/*.dwc2",    # DesignWare USB2 Controller
        "/sys/bus/platform/devices/*.dwc3",    # DesignWare USB3 Controller
        "/sys/bus/platform/devices/*.ci_hdrc", # ChipIdea controller
        "/sys/bus/platform/devices/*.musb",    # Mentor USB controller
      ]

      controllers.each do |pattern|
        Dir.glob(pattern).each do |path|
          if Dir.exists?(path)
            # Check if the device has dr_mode (device mode) or otg capability
            if File.exists?("#{path}/dr_mode") || File.exists?("#{path}/otg")
              Log.debug { "Found OTG-capable USB device controller: #{path}" }
              found_controller = true
              break
            end
          end
        end
        break if found_controller
      end
    end

    unless found_controller
      Log.warn { "No USB device controller found" }
    end

    found_controller
  end

  # Check if video input devices are available
  def self.video_input_available? : Bool
    # Check for video devices in /dev
    video_devices = Dir.glob("/dev/video*")
    if video_devices.empty?
      Log.warn { "No video devices found in /dev/video*" }
      return false
    end

    # Try to validate at least one device
    video_devices.each do |device|
      begin
        if File.exists?(device)
          # Additional check for readability
          begin
            File.open(device, "r") { |_| }
            Log.debug { "Found video device: #{device}" }
            return true
          rescue
            next
          end
        end
      rescue
        # Ignore errors when checking device
      end
    end

    Log.warn { "No valid video devices found" }
    false
  end

  # Detect the best video device
  def self.detect_best_video_device(width = 1920_u32, height = 1080_u32) : String?
    return nil unless video_input_available?

    begin
      detected_device = V4crVideoUtils.find_best_capture_device(width, height)
      if detected_device
        return detected_device.device
      end
    rescue ex
      Log.error { "Error detecting video device: #{ex.message}" }
    end

    nil
  end

  # Get hardware status summary
  def self.hardware_status : NamedTuple(
    otg_available: Bool,
    video_available: Bool,
    best_video_device: String?)
    otg_available = otg_hardware_available?
    video_available = video_input_available?
    best_video_device = video_available ? detect_best_video_device : nil

    {
      otg_available:     otg_available,
      video_available:   video_available,
      best_video_device: best_video_device,
    }
  end
end

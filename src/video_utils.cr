require "v4cr"

# V4cr-based video device detection utilities
module V4crVideoUtils
  Log = ::Log.for(self)

  struct V4crVideoDevice
    property device : String
    property name : String
    property driver : String
    property card : String
    property formats : Array(String)
    property resolutions : Array(String)
    property max_fps : Int32
    property? supports_mjpeg : Bool

    def initialize(@device : String, @name : String = "", @driver : String = "",
                   @card : String = "", @formats = [] of String,
                   @resolutions = [] of String, @max_fps = 0, @supports_mjpeg = false)
    end

    def supports_resolution?(width : UInt32, height : UInt32)
      target = "#{width}x#{height}"
      resolutions.any? { |res| res == target }
    end

    def to_s(io)
      io << "#{device} (#{card})"
      io << " - MJPEG: #{supports_mjpeg? ? "✅" : "❌"}"
      io << " - Formats: #{formats.join(", ")}"
      io << " - Max FPS: #{max_fps}"
    end
  end

  # Detect all available V4L2 video capture devices using V4cr
  def self.detect_video_devices : Array(V4crVideoDevice)
    devices = [] of V4crVideoDevice

    # Find all video devices
    0.upto(9) do |i|
      device_path = "/dev/video#{i}"
      next unless File.exists?(device_path)

      device = detect_device_info(device_path)
      if device
        devices << device
        Log.debug { "Found device: #{device}" }
      end
    end

    devices
  end

  # Get detailed information about a specific video device using V4cr
  def self.detect_device_info(device_path : String) : V4crVideoDevice?
    device = V4cr::Device.new(device_path)
    device.open

    # Check if device supports video capture
    capability = device.query_capability
    unless capability.video_capture?
      Log.debug { "#{device_path}: Not a video capture device" }
      device.close
      return nil
    end

    card = capability.card
    driver = capability.driver

    formats = [] of String
    resolutions = [] of String
    max_fps = 0
    supports_mjpeg = false

    begin
      device.supported_formats.each do |format|
        # Accept both 'MJPEG' and 'MJPG' as MJPEG
        if format.format_name.upcase.in?({"MJPEG", "MJPG"})
          supports_mjpeg = true
        end
        formats << format.format_name unless formats.includes?(format.format_name)
        # List all supported resolutions for this format, only allow WxH pattern
        device.supported_resolutions(format.pixelformat).each do |res|
          res_str = "#{res[:width]}x#{res[:height]}"
          # Only add if both width and height are > 0 and string matches WxH
          if res[:width] > 0 && res[:height] > 0 && res_str =~ /^\d+x\d+$/
            resolutions << res_str unless resolutions.includes?(res_str)
          end
        end
      end
    rescue e
      Log.debug { "#{device_path}: Error enumerating formats/resolutions: #{e.message}" }
    end

    device.close

    if formats.size > 0
      # Only keep valid WxH resolutions, filter out any non-matching entries (like 'jpeg')
      clean_resolutions = resolutions.select { |res_str| res_str =~ /^\d+x\d+$/ }
      V4crVideoDevice.new(
        device: device_path,
        name: card,
        driver: driver,
        card: card,
        formats: formats,
        resolutions: clean_resolutions.uniq.sort!,
        max_fps: max_fps.to_i32,
        supports_mjpeg: supports_mjpeg
      )
    else
      Log.debug { "#{device_path}: No supported formats found" }
      nil
    end
  rescue e
    Log.debug { "#{device_path}: Error accessing device: #{e.message}" }
    nil
  end

  # Find the best video device for capture
  def self.find_best_capture_device(preferred_width : UInt32 = 1920_u32, preferred_height : UInt32 = 1080_u32) : V4crVideoDevice?
    devices = detect_video_devices

    if devices.empty?
      Log.error { "No video capture devices found" }
      return nil
    end

    Log.info { "Detected video devices:" }
    devices.each_with_index do |device, index|
      Log.info { "  #{index + 1}. #{device}" }
    end

    # Prefer devices that support MJPEG
    mjpeg_devices = devices.select(&.supports_mjpeg?)

    if mjpeg_devices.empty?
      Log.warn { "No devices support MJPEG - using first available device" }
      Log.warn { "Note: This may result in poor streaming performance" }
      return devices.first
    end

    # Find device that supports the preferred resolution
    target_devices = mjpeg_devices.select { |device| device.supports_resolution?(preferred_width, preferred_height) }

    if target_devices.empty?
      Log.warn { "No MJPEG devices support #{preferred_width}x#{preferred_height} - using first MJPEG device" }
      return mjpeg_devices.first
    end

    # Return the first device that supports both MJPEG and target resolution
    best_device = target_devices.first
    Log.info { "Selected: #{best_device.device} - supports MJPEG at #{preferred_width}x#{preferred_height}" }
    best_device
  end

  # Validate that a specific device can capture video using V4cr
  def self.validate_device(device_path : String, width : UInt32, height : UInt32, fps : Int32) : Bool
    unless File.exists?(device_path)
      Log.error { "Video device #{device_path} does not exist" }
      return false
    end

    device_info = detect_device_info(device_path)
    unless device_info
      Log.error { "#{device_path} is not a valid video capture device" }
      return false
    end

    unless device_info.supports_mjpeg?
      Log.warn { "#{device_path} does not support MJPEG format" }
      Log.warn { "Available formats: #{device_info.formats.join(", ")}" }
    end

    unless device_info.supports_resolution?(width, height)
      Log.warn { "#{device_path} does not support #{width}x#{height} resolution" }
      Log.warn { "Available resolutions: #{device_info.resolutions.join(", ")}" }
    end

    if fps > device_info.max_fps
      Log.warn { "#{device_path} max FPS is #{device_info.max_fps}, requested #{fps}" }
    end

    # Test if we can actually open and configure the device
    begin
      test_device = V4cr::Device.new(device_path)
      test_device.open

      # Try to set the requested format
      test_device.set_format(width, height, V4cr::LibV4L2::V4L2_PIX_FMT_MJPG)

      # Try to request buffers (this will fail if device is busy)
      test_device.request_buffers(2)

      test_device.close
      Log.info { "#{device_path} V4cr validation passed" }
      true
    rescue e
      Log.error { "#{device_path} V4cr validation failed: #{e.message}" }
      false
    end
  end
end

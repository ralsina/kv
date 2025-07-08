require "process"

# Video device detection and validation utilities
module VideoUtils
  Log = ::Log.for(self)

  struct VideoDevice
    property device : String
    property name : String
    property formats : Array(String)
    property resolutions : Array(String)
    property max_fps : Int32

    def initialize(@device : String, @name : String = "", @formats = [] of String, @resolutions = [] of String, @max_fps = 0)
    end

    def supports_mjpeg?
      formats.any? { |format| format.upcase.includes?("MJPG") || format.upcase.includes?("MJPEG") }
    end

    def supports_resolution?(width : Int32, height : Int32)
      target = "#{width}x#{height}"
      resolutions.any? { |res| res == target }
    end

    def to_s(io)
      io << "#{device} (#{name})"
      io << " - MJPEG: #{supports_mjpeg? ? "✅" : "❌"}"
      io << " - Max FPS: #{max_fps}"
    end
  end

  # Detect all available video capture devices
  def self.detect_video_devices : Array(VideoDevice)
    devices = [] of VideoDevice

    # Find all video devices
    Dir.glob("/dev/video*").sort.each do |device_path|
      next unless File.exists?(device_path)

      device = detect_device_info(device_path)
      if device && device.formats.size > 0
        devices << device
      end
    end

    devices
  end

  # Get detailed information about a specific video device
  private def self.detect_device_info(device_path : String) : VideoDevice?
    # Check if device supports video capture inputs
    inputs_output = IO::Memory.new
    inputs_error = IO::Memory.new
    inputs_result = Process.run("v4l2-ctl", ["--device=#{device_path}", "--list-inputs"],
      output: inputs_output, error: inputs_error)

    unless inputs_result.success?
      Log.debug { "#{device_path}: Not a capture device" }
      return nil
    end

    # Get device name
    name = get_device_name(device_path)

    # Get supported formats and resolutions
    formats_output = IO::Memory.new
    formats_error = IO::Memory.new
    formats_result = Process.run("v4l2-ctl", ["--device=#{device_path}", "--list-formats-ext"],
      output: formats_output, error: formats_error)

    unless formats_result.success?
      Log.debug { "#{device_path}: Failed to get formats" }
      return nil
    end

    formats, resolutions, max_fps = parse_formats_output(formats_output.to_s)

    if formats.empty?
      Log.debug { "#{device_path}: No supported formats found" }
      return nil
    end

    VideoDevice.new(device_path, name, formats, resolutions, max_fps)
  end

  # Get the device name/description
  private def self.get_device_name(device_path : String) : String
    output = IO::Memory.new
    error = IO::Memory.new
    result = Process.run("v4l2-ctl", ["--device=#{device_path}", "--info"],
      output: output, error: error)

    if result.success?
      output.to_s.each_line do |line|
        if line.includes?("Card type")
          return line.split(":")[1]?.try(&.strip) || "Unknown"
        end
      end
    end

    "Unknown Device"
  end

  # Parse the output of v4l2-ctl --list-formats-ext
  private def self.parse_formats_output(output : String) : {Array(String), Array(String), Int32}
    formats = [] of String
    resolutions = [] of String
    max_fps = 0

    current_format = ""

    output.each_line do |line|
      line = line.strip

      # Format line: [0]: 'MJPG' (Motion-JPEG, compressed)
      if match = line.match(/\[(\d+)\]:\s+'([^']+)'\s+\(([^)]+)\)/)
        current_format = match[2]
        formats << current_format unless formats.includes?(current_format)
      end

      # Size line: Size: Discrete 1920x1080
      if match = line.match(/Size: Discrete (\d+x\d+)/)
        resolution = match[1]
        resolutions << resolution unless resolutions.includes?(resolution)
      end

      # Interval line: Interval: Discrete 0.033s (30.000 fps)
      if match = line.match(/Interval: Discrete [0-9.]+s \(([0-9.]+) fps\)/)
        fps = match[1].to_f.to_i
        max_fps = fps if fps > max_fps
      end
    end

    {formats, resolutions.uniq.sort!, max_fps}
  end

  # Find the best video device for capture
  def self.find_best_capture_device(preferred_width : Int32 = 1920, preferred_height : Int32 = 1080) : VideoDevice?
    devices = detect_video_devices

    if devices.empty?
      Log.error { "No video capture devices found" }
      return nil
    end

    Log.info { "Detected video devices:" }
    devices.each_with_index do |device, index|
      Log.info { "  #{index + 1}. #{device}" }
    end
    Log.info { "" }

    # Prefer devices that support MJPEG and the target resolution
    mjpeg_devices = devices.select(&.supports_mjpeg?)

    if mjpeg_devices.empty?
      Log.warn { "No devices support MJPEG - using first available device" }
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

  # Validate that a specific device can capture video
  def self.validate_device(device_path : String, width : Int32, height : Int32, fps : Int32) : Bool
    unless File.exists?(device_path)
      Log.error { "Video device #{device_path} does not exist" }
      return false
    end

    device = detect_device_info(device_path)
    unless device
      Log.error { "#{device_path} is not a valid video capture device" }
      return false
    end

    unless device.supports_mjpeg?
      Log.warn { "#{device_path} does not support MJPEG format" }
    end

    unless device.supports_resolution?(width, height)
      Log.warn { "#{device_path} does not support #{width}x#{height} resolution" }
      Log.warn { "    Available resolutions: #{device.resolutions.join(", ")}" }
    end

    if fps > device.max_fps
      Log.warn { "#{device_path} max FPS is #{device.max_fps}, requested #{fps}" }
    end

    # Test if we can actually open the device with FFmpeg
    output = IO::Memory.new
    error = IO::Memory.new
    test_result = Process.run("timeout", ["5", "ffmpeg", "-f", "v4l2", "-i", device_path, "-frames:v", "1", "-f", "null", "-"],
      output: output, error: error)

    if test_result.success?
      Log.info { "#{device_path} FFmpeg test passed" }
      true
    else
      Log.error { "#{device_path} FFmpeg test failed:" }
      Log.error { "   #{error.to_s.lines.last?}" }
      false
    end
  end
end

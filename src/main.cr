require "log"
require "kemal"
require "option_parser"
require "./kvm_manager"
require "./endpoints"
require "./video_utils"

module Main
  Log = ::Log.for("main")

  # Check for libcomposite kernel module and load if missing
  def self.ensure_libcomposite_loaded
    lsmod = `lsmod | grep libcomposite 2>/dev/null`
    if lsmod.strip.empty?
      Log.info { "libcomposite kernel module not loaded. Attempting to load..." }
      result = `modprobe libcomposite 2>&1`
      if $?.success?
        Log.info { "libcomposite module loaded successfully." }
      else
        Log.error { "Failed to load libcomposite: #{result}" }
        Log.error { "Please ensure you have the necessary permissions (run as root) and kernel support." }
        exit 1
      end
    else
      Log.info { "libcomposite kernel module is already loaded." }
    end
  end

  def self.main
    ensure_libcomposite_loaded

    # Perform a full system cleanup before starting the application
    # This is critical to prevent "device or resource busy" errors on restart
    KVMManager.perform_system_cleanup

    # Global KVM manager with configurable parameters
    video_device = "" # Will be auto-detected if not specified
    width = 1920
    height = 1080
    fps = 30
    quality = 85 # JPEG quality (1-100, higher = better quality)
    port = 3000
    auto_detect = true

    # Parse command line arguments
    OptionParser.parse do |parser|
      parser.banner = "Usage: kv [options]"

      parser.on("-d DEVICE", "--device=DEVICE", "Video device (default: auto-detect)") do |device|
        video_device = device
        auto_detect = false
      end

      parser.on("-r RESOLUTION", "--resolution=RESOLUTION", "Video resolution WIDTHxHEIGHT (default: 1920x1080)") do |resolution|
        # Handle common resolution shortcuts
        case resolution.downcase
        when "4k", "uhd"
          width, height = 3840, 2160
        when "1440p", "qhd"
          width, height = 2560, 1440
        when "1080p", "fhd"
          width, height = 1920, 1080
        when "720p", "hd"
          width, height = 1280, 720
        when "480p"
          width, height = 854, 480
        when "360p"
          width, height = 640, 360
        else
          if resolution =~ /^(\d+)x(\d+)$/
            width = $1.to_i
            height = $2.to_i
          else
            Log.error { "Invalid resolution format. Use WIDTHxHEIGHT (e.g., 1920x1080) or shortcuts:" }
            Log.error { "  4k/uhd (3840x2160), 1440p/qhd (2560x1440), 1080p/fhd (1920x1080)" }
            Log.error { "  720p/hd (1280x720), 480p (854x480), 360p (640x360)" }
            exit 1
          end
        end
      end

      parser.on("-f FPS", "--fps=FPS", "Video framerate (default: 30)") do |framerate|
        fps = framerate.to_i
        if fps <= 0 || fps > 60
          Log.error { "Invalid framerate. Must be between 1 and 60" }
          exit 1
        end
      end

      parser.on("-q QUALITY", "--quality=QUALITY", "JPEG quality 1-100 (default: 85, higher = better quality)") do |qual|
        quality = qual.to_i
        if quality < 1 || quality > 100
          Log.error { "Invalid quality. Must be between 1 and 100" }
          exit 1
        end
      end

      parser.on("-p PORT", "--port=PORT", "HTTP server port (default: 3000)") do |server_port|
        port = server_port.to_i
        if port <= 0 || port > 65535
          Log.error { "Invalid port. Must be between 1 and 65535" }
          exit 1
        end
      end

      parser.on("-h", "--help", "Show this help") do
        Log.info { parser.to_s }
        Log.info { "" }
        Log.info { "Examples:" }
        Log.info { "  sudo ./bin/kv                           # Auto-detect video device, 1080p@30fps, quality 85%" }
        Log.info { "  sudo ./bin/kv -r 720p -f 60 -q 95      # Auto-detect device, HD 720p at 60fps, high quality" }
        Log.info { "  sudo ./bin/kv -d /dev/video0 -r 4k     # Specific device, 4K resolution" }
        Log.info { "  sudo ./bin/kv -r 1280x720 -p 8080 -q 70 # Custom resolution, port 8080, medium quality" }
        exit 0
      end

      parser.invalid_option do |flag|
        Log.error { "ERROR: #{flag} is not a valid option." }
        Log.error { parser.to_s }
        exit 1
      end
    end

    # Auto-detect video device if not specified
    if auto_detect || video_device.empty?
      Log.info { "Auto-detecting video capture device..." }

      if detected_device = VideoUtils.find_best_capture_device(width, height)
        video_device = detected_device.device
      else
        Log.error { "No suitable video capture device found" }
        Log.error { "   Please specify a device manually with -d /dev/videoX" }
        exit 1
      end
    else
      # Validate the manually specified device
      Log.info { "Validating specified video device: #{video_device}" }
      if VideoUtils.validate_device(video_device, width, height, fps)
        Log.info { "" }
      else
        Log.warn { "Device validation failed. Continuing anyway..." }
        Log.info { "" }
      end
    end

    # Create and set the global KVM manager instance
    kvm_manager = KVMManager.new(video_device, width, height, fps, quality)
    GlobalKVM.set_manager(kvm_manager)

    # Cleanup on exit
    at_exit do
      kvm_manager.cleanup
    end

    Log.info { "" }
    Log.info { "🖥️  Ultra Low-Latency KVM Server" }
    Log.info { "━" * 50 }
    Log.info { "📹 Video device: #{kvm_manager.video_device}" }
    Log.info { "📐 Resolution: #{kvm_manager.width}x#{kvm_manager.height}@#{kvm_manager.fps}fps" }
    Log.info { "📸 Quality: #{kvm_manager.quality}%" }
    Log.info { "🌐 Web interface: http://localhost:#{port}" }
    Log.info { "📡 MJPEG stream: http://localhost:#{port}/video.mjpg" }
    Log.info { "⌨️  HID keyboard: #{kvm_manager.keyboard_enabled? ? "✅ Ready" : "❌ Disabled"}" }
    Log.info { "🖱️  HID mouse: #{kvm_manager.mouse_enabled? ? "✅ Ready" : "❌ Disabled"}" }
    Log.info { "⚡ Architecture: Direct MJPEG + USB HID" }
    Log.info { "🎯 Target latency: <100ms" }
    Log.info { "" }
    Log.warn { "⚠️  Note: HID keyboard and mouse require root privileges and USB OTG support" }
    Log.warn { "   Run with: sudo ./bin/kv" }
    Log.info { "" }
    Log.info { "💡 Configuration:" }
    Log.info { "   Video device: #{video_device}" }
    Log.info { "   Resolution: #{width}x#{height}" }
    Log.info { "   Framerate: #{fps} fps" }
    Log.info { "   Quality: #{quality}%" }
    Log.info { "   Server port: #{port}" }
    Log.info { "" }
    Log.info { "Inspired by raspivid_mjpeg_server design principles" }
    Log.info { "for minimal latency streaming." }
    Log.info { "" }

    Kemal.run(port: port)
  end
end

Main.main

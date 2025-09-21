require "log"
require "kemal"
require "docopt"
require "./kvm_manager"
require "./endpoints"
require "./video_utils"
require "baked_file_system"
require "baked_file_handler"
require "kemal-basic-auth"
require "./anti_idle"
require "./hardware_detector"

module Main
  VERSION = {{ `shards version #{__DIR__}/../`.chomp.stringify }}
  Log     = ::Log.for("main")

  class Assets
    extend BakedFileSystem
    bake_folder "../assets"
  end

  # Check for libcomposite kernel module and load if missing
  def self.ensure_libcomposite_loaded
    lsmod = `lsmod | grep libcomposite 2>/dev/null`
    if lsmod.strip.empty?
      Log.info { "libcomposite kernel module not loaded. Attempting to load..." }
      result = `modprobe libcomposite 2>&1`
      if $?.success?
        Log.info { "libcomposite module loaded successfully." }
      else
        Log.warn { "Failed to load libcomposite: #{result}" }
        Log.warn { "USB gadget functionality will not be available" }
        return false
      end
    else
      Log.info { "libcomposite kernel module is already loaded." }
    end
    true
  end

  def self.main
    usage = <<-USAGE
      Ultra Low-Latency KVM Server (V4cr)

      Usage:
        kv [options]

      Options:
        -d DEVICE, --device=DEVICE         Video device [default: auto-detect]
        -a DEVICE, --audio-device=DEVICE   Audio device [default: hw:1,0]
        -r RESOLUTION, --resolution=RESOLUTION  Video resolution WIDTHxHEIGHT [default: 1920x1080]
        -f FPS, --fps=FPS                  Video framerate [default: 30]
        -q QUALITY, --quality=QUALITY      Video JPEG quality (1-100) [default: 100]
        -p PORT, --port=PORT               HTTP server port [default: 3000]
        -b ADDRESS, --bind=ADDRESS         Address to bind to [default: 0.0.0.0]
        --disable-mouse                   Disable USB mouse gadget
        --disable-ethernet                 Disable USB ethernet gadget
        --disable-mass-storage             Disable USB mass storage gadget
        --anti-idle                        Enable anti-idle mouse jiggler every 60 seconds
        --hotplug-interval=SECONDS         Video device hotplug polling interval [default: 60]
        -h, --help                         Show this help

      Environment Variables:
        LOG_LEVEL                          Log level (debug, info, warn, error, fatal) [default: info]
        KV_USER                            Username for basic authentication
        KV_PASSWORD                        Password for basic authentication

      Examples:
        sudo ./bin/kv                          # Auto-detect video device, 1080p@30fps
        sudo ./bin/kv -r 720p -f 60            # Auto-detect device, HD 720p at 60fps
        sudo ./bin/kv -d /dev/video0 -r 4k     # Specific device, 4K resolution
        sudo ./bin/kv -r 1280x720 -p 8080      # Custom resolution, port 8080
        LOG_LEVEL=debug sudo ./bin/kv          # Enable debug logging
      USAGE

    args = Docopt.docopt(usage, ARGV, version: VERSION)

    # Check hardware availability first
    hw_status = HardwareDetector.hardware_status
    Log.info { "Hardware detection results:" }
    Log.info { "  USB OTG: #{hw_status[:otg_available] ? "✅ Available" : "❌ Not available"}" }
    Log.info { "  Video Input: #{hw_status[:video_available] ? "✅ Available" : "❌ Not available"}" }
    if hw_status[:best_video_device]
      Log.info { "  Best video device: #{hw_status[:best_video_device]}" }
    end

    # Only try to load libcomposite if OTG is available
    otg_supported = hw_status[:otg_available] && ensure_libcomposite_loaded

    KVMManagerV4cr.perform_system_cleanup

    # Basic Auth setup
    user = ENV["KV_USER"]?
    pass = ENV["KV_PASSWORD"]?
    if (user && !pass) || (!user && pass)
      Log.error { "Both KV_USER and KV_PASSWORD must be set for basic authentication." }
      exit 1
    elsif user && pass
      Log.info { "🔒 Basic authentication enabled (user: #{user})" }
      basic_auth user, pass
    else
      Log.info { "🔓 Basic authentication is disabled (KV_USER and KV_PASSWORD not set)" }
    end

    # Extract options from docopt result
    video_device = args["--device"]?.try(&.as(String)) || ""
    audio_device = args["--audio-device"]?.try(&.as(String)) || "hw:1,0"
    resolution = args["--resolution"]?.try(&.as(String)) || "1920x1080"
    fps = args["--fps"]?.try(&.as(String)) || "30"
    jpeg_quality = args["--quality"]?.try(&.as(String)) || "100"
    port = args["--port"]?.try(&.as(String)) || "3000"
    bind_address = args["--bind"]?.try(&.as(String)) || "0.0.0.0"
    hotplug_interval = args["--hotplug-interval"]?.try(&.as(String)) || "60"
    auto_detect = video_device.empty? || video_device == "auto-detect"

    # Parse resolution
    width = 1920_u32
    height = 1080_u32
    case resolution.downcase
    when "4k", "uhd"
      width, height = 3840_u32, 2160_u32
    when "1440p", "qhd"
      width, height = 2560_u32, 1440_u32
    when "1080p", "fhd"
      width, height = 1920_u32, 1080_u32
    when "720p", "hd"
      width, height = 1280_u32, 720_u32
    when "480p"
      width, height = 854_u32, 480_u32
    when "360p"
      width, height = 640_u32, 360_u32
    else
      if match = resolution.match(/^(\d+)x(\d+)$/)
        width = match[1].to_u32
        height = match[2].to_u32
      else
        Log.error { "Invalid resolution format. Use WIDTHxHEIGHT (e.g., 1920x1080) or shortcuts:" }
        Log.error { "  4k/uhd (3840x2160), 1440p/qhd (2560x1440), 1080p/fhd (1920x1080)" }
        Log.error { "  720p/hd (1280x720), 480p (854x480), 360p (640x360)" }
        exit 1
      end
    end

    # Parse fps, jpeg_quality and port
    fps = fps.to_i
    if fps <= 0 || fps > 60
      Log.error { "Invalid framerate. Must be between 1 and 60" }
      exit 1
    end
    jpeg_quality = jpeg_quality.to_i
    if jpeg_quality <= 0 || jpeg_quality > 100
      Log.error { "Invalid JPEG quality. Must be between 1 and 100" }
      exit 1
    end
    port = port.to_i
    if port <= 0 || port > 65535
      Log.error { "Invalid port. Must be between 1 and 65535" }
      exit 1
    end

    # Parse hotplug interval
    hotplug_interval = hotplug_interval.to_i
    if hotplug_interval < 0
      Log.error { "Invalid hotplug interval. Must be 0 or positive" }
      exit 1
    end

    # Auto-detect or validate video device
    video_available = false
    if video_device.empty? || auto_detect
      Log.info { "No video device specified, attempting auto-detection..." }
      detected_device = V4crVideoUtils.find_best_capture_device(width, height)
      if detected_device
        video_device = detected_device.device
        video_available = true
        Log.info { "Auto-detected video device: #{video_device}" }
      else
        Log.warn { "⚠️  No suitable video capture device found!" }
        Log.warn { "   Video streaming will not be available" }
        video_device = "" # Clear the device to indicate no video
      end
    else
      Log.info { "Validating specified video device: #{video_device}" }
      if V4crVideoUtils.validate_device(video_device, width, height, fps)
        video_available = true
      else
        Log.warn { "⚠️  Specified device #{video_device} is not valid or not available!" }
        Log.warn { "   Video streaming will not be available" }
        video_device = "" # Clear the device to indicate no video
      end
    end

    # If no video is available initially but hotplug is enabled, we'll poll
    enable_hotplug = !video_available && hotplug_interval > 0

    # If neither video nor OTG is available and hotplug is disabled, exit
    if !video_available && !otg_supported && !enable_hotplug
      Log.error { "❌ Neither video input nor USB OTG is available. Cannot start KVM service." }
      Log.error { "   Use --hotplug-interval > 0 to enable video device hotplug polling" }
      exit 1
    end

    # Extract disable flags
    disable_mouse = false
    disable_ethernet = false
    disable_mass_storage = false
    disable_mouse = true if args["--disable-mouse"]
    disable_ethernet = true if args["--disable-ethernet"]
    disable_mass_storage = true if args["--disable-mass-storage"]

    # Create and set the global KVM manager instance
    kvm_manager = KVMManagerV4cr.new(
      video_device,
      audio_device,
      width,
      height,
      fps,
      jpeg_quality,
      ecm_enabled: false, # Not passed from CLI, will be set based on hardware
      disable_mouse: disable_mouse,
      disable_ethernet: disable_ethernet,
      disable_mass_storage: disable_mass_storage,
      hotplug_interval: hotplug_interval.seconds
    )
    GlobalKVM.manager = kvm_manager

    # Configure and start AntiIdle service
    anti_idle_enabled = false
    anti_idle_enabled = true if args["--anti-idle"]
    if anti_idle_enabled
      interval = 1
      AntiIdle.configure(enabled: true, interval: interval.seconds)
      AntiIdle.start(kvm_manager)
      Log.info { "Anti-idle mouse jiggler is enabled with a #{interval} second interval." }
    end

    # Cleanup on exit
    at_exit do
      AntiIdle.stop if anti_idle_enabled
      kvm_manager.stop_hotplug_polling
      kvm_manager.cleanup
    end

    Log.info { "" }
    # Print mode-specific information
    if video_available && otg_supported
      Log.info { "🖥️  Ultra Low-Latency KVM Server (V4cr) - Full KVM Mode" }
      Log.info { "━" * 50 }
      Log.info { "📹 Video device: #{kvm_manager.video_device}" }
      Log.info { "📐 Resolution: #{kvm_manager.width}x#{kvm_manager.height}@#{kvm_manager.fps}fps" }
      Log.info { "🌐 Web interface: http://localhost:#{port}" }
      Log.info { "📡 MJPEG stream: http://localhost:#{port}/video.mjpg" }
      Log.info { "⌨️  HID keyboard: #{kvm_manager.keyboard_enabled? ? "✅ Ready" : "❌ Disabled"}" }
      Log.info { "🖱️  HID mouse: #{kvm_manager.mouse_disabled? ? "❌ Disabled by command line" : (kvm_manager.mouse_enabled? ? "✅ Ready" : "❌ Failed to initialize")}" }
      Log.info { "🔌 Ethernet gadget: #{kvm_manager.ethernet_disabled? ? "❌ Disabled by command line" : (kvm_manager.ecm_status[:enabled] ? "✅ Ready" : "❌ Failed to initialize")}" }
      Log.info { "💾 Mass storage gadget: #{kvm_manager.mass_storage_disabled? ? "❌ Disabled by command line" : (kvm_manager.status[:storage][:attached] ? "✅ Ready" : "⏸️ Idle (no image selected)")}" }
      Log.info { "⚡ Architecture: Direct V4cr MJPEG + USB HID" }
      Log.info { "🎯 Target latency: <50ms" }
    elsif video_available && !otg_supported
      Log.info { "🖥️  Ultra Low-Latency KVM Server (V4cr) - Video Streaming Mode" }
      Log.info { "━" * 50 }
      Log.info { "📹 Video device: #{kvm_manager.video_device}" }
      Log.info { "📐 Resolution: #{kvm_manager.width}x#{kvm_manager.height}@#{kvm_manager.fps}fps" }
      Log.info { "🌐 Web interface: http://localhost:#{port}" }
      Log.info { "📡 MJPEG stream: http://localhost:#{port}/video.mjpg" }
      Log.info { "⚠️  USB OTG not available - HID devices disabled" }
      Log.info { "⚡ Architecture: Direct V4cr MJPEG (video only)" }
    elsif !video_available && otg_supported
      Log.info { "🖥️  Ultra Low-Latency KVM Server (V4cr) - Input Mode" }
      Log.info { "━" * 50 }
      Log.info { "🌐 Web interface: http://localhost:#{port}" }
      Log.info { "⌨️  HID keyboard: #{kvm_manager.keyboard_enabled? ? "✅ Ready" : "❌ Disabled"}" }
      Log.info { "🖱️  HID mouse: #{kvm_manager.mouse_disabled? ? "❌ Disabled by command line" : (kvm_manager.mouse_enabled? ? "✅ Ready" : "❌ Failed to initialize")}" }
      Log.info { "🔌 Ethernet gadget: #{kvm_manager.ethernet_disabled? ? "❌ Disabled by command line" : (kvm_manager.ecm_status[:enabled] ? "✅ Ready" : "❌ Failed to initialize")}" }
      Log.info { "💾 Mass storage gadget: #{kvm_manager.mass_storage_disabled? ? "❌ Disabled by command line" : (kvm_manager.status[:storage][:attached] ? "✅ Ready" : "⏸️ Idle (no image selected)")}" }
      Log.info { "⚡ Architecture: USB HID (input only)" }
      Log.warn { "⚠️  Video input not available - video streaming disabled" }
      if enable_hotplug
        Log.info { "🔄 Hotplug polling enabled (checking every #{hotplug_interval}s)" }
      end
    end
    Log.info { "" }
    if otg_supported
      Log.warn { "⚠️  Note: HID keyboard and mouse require root privileges" }
      Log.warn { "   Run with: sudo ./bin/kv" }
    end
    Log.info { "" }
    Log.info { "💡 Configuration:" }
    Log.info { "   Video device: #{video_device}" }
    Log.info { "   Resolution: #{width}x#{height}" }
    Log.info { "   Framerate: #{fps} fps" }
    Log.info { "   JPEG Quality: #{jpeg_quality}" }
    Log.info { "   Server port: #{port}" }
    Log.info { "" }
    Log.info { "V4cr implementation for zero-copy video streaming" }
    Log.info { "with native V4L2 access for minimal latency." }
    Log.info { "" }

    add_handler BakedFileHandler::BakedFileHandler.new(Assets)
    # Enable CORS for all origins (allow cross-origin requests) on all responses
    before_all do |env|
      env.response.headers.add("Access-Control-Allow-Origin", "*")
    end
    # Configure log level based on environment variable
    log_level = ENV.fetch("LOG_LEVEL", "info").downcase
    case log_level
    when "debug"
      ::Log.setup("*", :debug)
    when "info"
      ::Log.setup("*", :info)
    when "warn"
      ::Log.setup("*", :warn)
    when "error"
      ::Log.setup("*", :error)
    when "fatal"
      ::Log.setup("*", :fatal)
    else
      ::Log.setup("*", :info)
    end
    ::Log.setup("kemal.*", :notice)
    Kemal.config.host_binding = bind_address
    ARGV.clear
    Kemal.run(port: port)
  end
end

Main.main

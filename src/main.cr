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
        Log.error { "Failed to load libcomposite: #{result}" }
        Log.error { "Please ensure you have the necessary permissions (run as root) and kernel support." }
        exit 1
      end
    else
      Log.info { "libcomposite kernel module is already loaded." }
    end
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
  -p PORT, --port=PORT               HTTP server port [default: 3000]
  -b ADDRESS, --bind=ADDRESS         Address to bind to [default: 0.0.0.0]
  --anti-idle                        Enable anti-idle mouse jiggler every 60 seconds
  -h, --help                         Show this help

Examples:
  sudo ./bin/kv                          # Auto-detect video device, 1080p@30fps
  sudo ./bin/kv -r 720p -f 60            # Auto-detect device, HD 720p at 60fps
  sudo ./bin/kv -d /dev/video0 -r 4k     # Specific device, 4K resolution
  sudo ./bin/kv -r 1280x720 -p 8080      # Custom resolution, port 8080
USAGE

    args = Docopt.docopt(usage, ARGV, version: VERSION)

    ensure_libcomposite_loaded
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
    port = args["--port"]?.try(&.as(String)) || "3000"
    bind_address = args["--bind"]?.try(&.as(String)) || "0.0.0.0"
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

    # Parse fps and port
    fps = fps.to_i
    if fps <= 0 || fps > 60
      Log.error { "Invalid framerate. Must be between 1 and 60" }
      exit 1
    end
    port = port.to_i
    if port <= 0 || port > 65535
      Log.error { "Invalid port. Must be between 1 and 65535" }
      exit 1
    end

    # Auto-detect or validate video device
    if video_device.empty? || auto_detect
      Log.info { "No video device specified, attempting auto-detection..." }
      detected_device = V4crVideoUtils.find_best_capture_device(width, height)
      if detected_device
        video_device = detected_device.device
        Log.info { "Auto-detected video device: #{video_device}" }
      else
        Log.error { "❌ No suitable video capture device found!" }
        Log.error { "   Please connect a V4L2-compatible device or specify one with -d /dev/videoX" }
        exit 1
      end
    else
      Log.info { "Validating specified video device: #{video_device}" }
      unless V4crVideoUtils.validate_device(video_device, width, height, fps)
        Log.error { "❌ Specified device #{video_device} is not valid or not available!" }
        exit 1
      end
    end

    # Create and set the global KVM manager instance
    kvm_manager = KVMManagerV4cr.new(video_device, audio_device, width, height, fps, fps)
    GlobalKVM.manager = kvm_manager

    # Configure and start AntiIdle service
    anti_idle_enabled = args.includes? "--anti-idle"
    if anti_idle_enabled
      interval = 1
      AntiIdle.configure(enabled: true, interval: interval.seconds)
      AntiIdle.start(kvm_manager)
      Log.info { "Anti-idle mouse jiggler is enabled with a #{interval} second interval." }
    end

    # Cleanup on exit
    at_exit do
      AntiIdle.stop if anti_idle_enabled
      kvm_manager.cleanup
    end

    Log.info { "" }
    Log.info { "🖥️  Ultra Low-Latency KVM Server (V4cr)" }
    Log.info { "━" * 50 }
    Log.info { "📹 Video device: #{kvm_manager.video_device}" }
    Log.info { "📐 Resolution: #{kvm_manager.width}x#{kvm_manager.height}@#{kvm_manager.fps}fps" }
    Log.info { "🌐 Web interface: http://localhost:#{port}" }
    Log.info { "📡 MJPEG stream: http://localhost:#{port}/video.mjpg" }
    Log.info { "⌨️  HID keyboard: #{kvm_manager.keyboard_enabled? ? "✅ Ready" : "❌ Disabled"}" }
    Log.info { "🖱️  HID mouse: #{kvm_manager.mouse_enabled? ? "✅ Ready" : "❌ Disabled"}" }
    Log.info { "⚡ Architecture: Direct V4cr MJPEG + USB HID" }
    Log.info { "🎯 Target latency: <50ms" }
    Log.info { "" }
    Log.warn { "⚠️  Note: HID keyboard and mouse require root privileges and USB OTG support" }
    Log.warn { "   Run with: sudo ./bin/kv" }
    Log.info { "" }
    Log.info { "💡 Configuration:" }
    Log.info { "   Video device: #{video_device}" }
    Log.info { "   Resolution: #{width}x#{height}" }
    Log.info { "   Framerate: #{fps} fps" }
    Log.info { "   Server port: #{port}" }
    Log.info { "" }
    Log.info { "V4cr implementation for zero-copy video streaming" }
    Log.info { "with native V4L2 access for minimal latency." }
    Log.info { "" }

    add_handler BakedFileHandler::BakedFileHandler.new(Assets)
    ::Log.setup("*", :info)
    ::Log.setup("kemal.*", :notice)
    Kemal.config.host_binding = bind_address
    ARGV.clear
    Kemal.run(port: port)
  end
end

Main.main

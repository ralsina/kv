require "./keyboard"
require "./mouse"
require "./composite"
require "./mass_storage_manager"
require "./video_capture"
require "./audio_streamer"
require "kemal"
require "file_utils"

# Global KVM manager module
module GlobalKVM
  Log = ::Log.for(self)

  @@manager : KVMManagerV4cr?

  def self.manager=(manager : KVMManagerV4cr)
    @@manager = manager
  end

  def self.manager
    if manager = @@manager
      manager
    else
      raise "KVM manager not initialized"
    end
  end
end

# Updated KVM manager using V4cr for video capture instead of FFmpeg
class KVMManagerV4cr
  def available_qualities : Array(String)
    # Only return real resolutions; the UI should handle JPEG quality separately
    @detected_qualities
  end

  def selected_quality : String
    "#{@width}x#{@height}"
  end

  # Change video quality (resolution@fps string)
  def video_quality=(quality : String) : Bool
    Log.info { "Attempting to set video quality to: #{quality}" }

    if quality.starts_with?("jpeg:")
      parts = quality.split(':')
      if parts.size == 2
        if new_quality = parts[1].to_i?
          if new_quality >= 1 && new_quality <= 100
            @video_jpeg_quality = new_quality
            @video_capture.jpeg_quality = @video_jpeg_quality
            Log.info { "Successfully set video JPEG quality to #{@video_jpeg_quality}" }
            return true
          else
            Log.warn { "JPEG quality out of range: #{new_quality}" }
            return false
          end
        else
          Log.warn { "Invalid JPEG quality value: #{parts[1]}" }
          return false
        end
      else
        Log.warn { "Invalid JPEG quality format: #{quality}" }
        return false
      end
    elsif quality.starts_with?("fps:")
      parts = quality.split(':')
      if parts.size == 2
        if new_fps = parts[1].to_i?
          if new_fps >= 1 && new_fps <= 60 # Assuming a reasonable FPS range
            @fps = new_fps
            @video_capture.fps = @fps
            Log.info { "Successfully set video FPS to #{@fps}" }
            return true
          else
            Log.warn { "FPS out of range: #{new_fps}" }
            return false
          end
        else
          Log.warn { "Invalid FPS value: #{parts[1]}" }
          return false
        end
      else
        Log.warn { "Invalid FPS format: #{quality}" }
        return false
      end
    elsif @detected_qualities.includes?(quality)
      if match = quality.match(/(\d+)x(\d+)/)
        width = match[1].to_u32
        height = match[2].to_u32
        if width != @width || height != @height
          Log.info { "Changing resolution to #{width}x#{height}" }
          stop_video_stream
          @width = width
          @height = height
          @video_capture = V4crVideoCapture.new(@video_device, @width, @height, @fps, @video_jpeg_quality)
          start_video_stream
        else
          Log.info { "Resolution is already set to #{quality}, no change needed." }
        end
        return true
      end
    end

    Log.warn { "Unsupported quality string: #{quality}" }
    false
  end

  # Upload and decompress a disk image, always storing as .img
  def upload_and_decompress_image(uploaded_path : String, orig_filename : String) : {success: Bool, message: String, filename: String?}
    disk_images_dir = "disk-images"
    FileUtils.mkdir_p(disk_images_dir) unless Dir.exists?(disk_images_dir)

    # Basic filename sanitization
    base_name = File.basename(orig_filename.gsub(/[^a-zA-Z0-9._-]/, "_"))
    base_name = base_name.sub(/\.(img|raw|iso|qcow2|gz|bz2|xz|zip)$/i, "")
    img_filename = base_name + ".img"
    dest_path = File.join(disk_images_dir, img_filename)

    # Detect compression type by extension and decompress
    ext = File.extname(orig_filename).downcase
    decompress_cmd = nil
    case ext
    when ".gz"
      decompress_cmd = "gunzip -c '#{uploaded_path}' > '#{dest_path}'"
    when ".bz2"
      decompress_cmd = "bunzip2 -c '#{uploaded_path}' > '#{dest_path}'"
    when ".xz"
      decompress_cmd = "xz -d -c '#{uploaded_path}' > '#{dest_path}'"
    when ".zip"
      decompress_cmd = "unzip -p '#{uploaded_path}' > '#{dest_path}'"
    when ".qcow2"
      decompress_cmd = "qemu-img convert -O raw '#{uploaded_path}' '#{dest_path}'"
    else
      # Assume raw or .img, just move/rename
      File.rename(uploaded_path, dest_path)
    end

    if decompress_cmd
      Process.run(decompress_cmd, shell: true)
      unless File.exists?(dest_path) && File.size(dest_path) > 0
        return {success: false, message: "Decompression failed", filename: nil}
      end
    end

    {success: true, message: "File uploaded and decompressed as .img", filename: img_filename}
  rescue ex
    {success: false, message: "Upload failed: #{ex.message}", filename: nil}
  end

  # Ensure the image is a raw .img file, return the raw image filename to use for mounting
  def ensure_decompressed_image(image : String?) : {success: Bool, raw_image: String?, message: String?}
    return {success: true, raw_image: nil, message: nil} unless image
    disk_images_dir = "disk-images"
    # The image should already be decompressed to .img during upload
    # Just verify its existence and return the path
    raw_path = File.join(disk_images_dir, image)
    unless File.exists?(raw_path)
      return {success: false, raw_image: nil, message: "Image file not found: #{image}. It might not have been uploaded or decompressed correctly."}
    end
    {success: true, raw_image: image, message: nil}
  rescue ex
    {success: false, raw_image: nil, message: ex.message}
  end

  Log = ::Log.for(self)

  @keyboard_enabled = false
  @mouse_enabled = false
  @ecm_enabled : Bool
  @video_device : String
  @audio_device : String
  @keyboard_device : String = ""
  @mouse_device : String = ""          # Relative mouse
  @mouse_device_absolute : String = "" # Absolute mouse
  @width : UInt32
  @height : UInt32
  @fps : Int32
  @pressed_buttons = Set(String).new
  @mass_storage : MassStorageManager
  @video_capture : V4crVideoCapture
  @video_jpeg_quality : Int32 = 100
  @detected_qualities : Array(String)
  @audio_streamer : AudioStreamer

  def initialize(@video_device = "/dev/video1", @audio_device = "hw:1,0", @width = 640_u32, @height = 480_u32, @fps = 30, @video_jpeg_quality = 100, ecm_enabled = false)
    @ecm_enabled = ecm_enabled
    @mass_storage = MassStorageManager.new
    @video_capture = V4crVideoCapture.new(@video_device, @width, @height, @fps, @video_jpeg_quality)
    @audio_streamer = AudioStreamer.new(@audio_device)

    # Detect available qualities from the video device
    detected_quality_objects = [] of {width: UInt32, height: UInt32}
    if device_info = V4crVideoUtils.detect_device_info(@video_device)
      device_info.resolutions.each do |res_str|
        if match = res_str.match(/(\d+)x(\d+)/)
          width = match[1].to_u32
          height = match[2].to_u32
          detected_quality_objects << {width: width, height: height}
        end
      end
    end

    # Sort qualities: highest resolution first, then highest
    @detected_qualities = detected_quality_objects.uniq.sort_by! do |quality_obj|
      [-quality_obj[:width].to_i32, -quality_obj[:height].to_i32]
    end.map do |quality_obj|
      "#{quality_obj[:width]}x#{quality_obj[:height]}"
    end

    # If no qualities detected, fall back to a default or raise error
    if @detected_qualities.empty?
      Log.warn { "No video qualities detected for #{@video_device}. Falling back to 640x480." }
      @detected_qualities << "640x480"
    end

    setup_hid_devices
    start_video_stream # Start video automatically
  end

  # Returns the absolute mouse device path
  def mouse_device_absolute
    @mouse_device_absolute
  end

  def setup_hid_devices
    storage_file = @mass_storage.selected_image
    enable_mass_storage = !!storage_file
    # Build status string for logging
    status_str = "Setting up USB HID composite gadget (keyboard + mouse"
    status_str += " + mass storage" if enable_mass_storage
    status_str += " + ECM/ethernet" if @ecm_enabled
    status_str += ")..."
    Log.info { status_str }
    Log.info { "Mass storage selected_image: " + (storage_file || "<none>") + ", enable_mass_storage: #{enable_mass_storage}" }

    devices = HIDComposite.setup_usb_composite_gadget(
      enable_mass_storage: enable_mass_storage,
      storage_file: storage_file,
      enable_ecm: @ecm_enabled
    )

    @keyboard_device = devices[:keyboard]
    @mouse_device = devices[:mouse]
    @mouse_device_absolute = devices[:mouse_absolute]
    @keyboard_enabled = File.exists?(@keyboard_device)
    @mouse_enabled = File.exists?(@mouse_device)

    Log.info { "HID keyboard ready: #{@keyboard_device}" }
    Log.info { "HID mouse (relative) ready: #{@mouse_device}" }
    Log.info { "HID mouse (absolute) ready: #{@mouse_device_absolute}" }

    if enable_mass_storage
      Log.info { "USB mass storage ready: #{storage_file}" }
    else
      Log.info { "No USB mass storage image attached (detached)" }
    end
  rescue ex
    Log.error { "Failed to setup HID composite gadget: #{ex.message}" }
    Log.error { "Make sure you're running as root and USB OTG is available" }
    @keyboard_enabled = false
    @mouse_enabled = false
  end

  def start_video_stream
    Log.info { "Starting V4cr video stream..." }
    success = @video_capture.start_streaming

    if success
      Log.info { "V4cr video stream started successfully" }
      if info = @video_capture.device_info
        Log.info { "Device: #{info[:card]} (#{info[:device]})" }
        Log.info { "Format: #{info[:format]} #{info[:width]}x#{info[:height]}" }
      end
    else
      Log.error { "Failed to start V4cr video stream" }
    end

    success
  end

  def stop_video_stream
    Log.info { "Stopping V4cr video stream..." }
    @video_capture.stop_streaming
    Log.info { "V4cr video stream stopped" }
  end

  def start_audio_stream(output_io : IO)
    Log.info { "Starting audio stream..." }
    @audio_streamer.start_streaming(output_io)
  end

  def stop_audio_stream
    Log.info { "Stopping audio stream..." }
    @audio_streamer.stop_streaming
  end

  def audio_running?
    @audio_streamer.running?
  end

  def video_running?
    @video_capture.running?
  end

  def keyboard_enabled?
    @keyboard_enabled
  end

  def mouse_enabled?
    @mouse_enabled
  end

  def send_keys(keys : Array(String), modifiers : Array(String) = [] of String)
    report = HIDKeyboard.create_keyboard_report(keys, modifiers)
    HIDKeyboard.send_keyboard_report(@keyboard_device.to_s, report)
    {success: true, message: "Keys sent: #{keys.join("+")}"}
  rescue ex
    Log.error { "Failed to send keys: #{ex.message}" }
    {success: false, message: "Error sending keys: #{ex.message}"}
  end

  def send_text(text : String)
    return {success: false, message: "Keyboard not available"} unless @keyboard_enabled
    return {success: false, message: "No keyboard device"} unless @keyboard_device

    begin
      Log.debug { "Sending text: '#{text}'" }
      HIDKeyboard.send_text(@keyboard_device, text)
      {success: true, message: "Text sent: #{text}"}
    rescue ex
      Log.error { "Failed to send text: #{ex.message}" }
      {success: false, message: "Error sending text: #{ex.message}"}
    end
  end

  def send_mouse_click(button : String)
    return {success: false, message: "Mouse not available"} unless @mouse_enabled
    return {success: false, message: "No mouse device"} unless @mouse_device

    begin
      HIDMouse.send_mouse_click(@mouse_device, button)
      {success: true, message: "Mouse click sent: #{button}"}
    rescue ex
      Log.error { "Failed to send mouse click: #{ex.message}" }
      {success: false, message: "Error sending mouse click: #{ex.message}"}
    end
  end

  def send_mouse_move(x : Int32, y : Int32)
    return {success: false, message: "Mouse not available"} unless @mouse_enabled
    return {success: false, message: "No mouse device"} unless @mouse_device

    begin
      # Send movement with current button state preserved
      HIDMouse.send_mouse_move_with_buttons(@mouse_device, x, y, @pressed_buttons.to_a)
      {success: true, message: "Mouse move sent: #{x}, #{y} with buttons: #{@pressed_buttons.to_a}"}
    rescue ex
      Log.error { "Failed to send mouse move: #{ex.message}" }
      {success: false, message: "Error sending mouse move: #{ex.message}"}
    end
  end

  def send_mouse_press(button : String)
    return {success: false, message: "Mouse not available"} unless @mouse_enabled
    return {success: false, message: "No mouse device"} unless @mouse_device

    begin
      @pressed_buttons.add(button) # Track pressed button
      HIDMouse.send_mouse_press(@mouse_device, button)
      {success: true, message: "Mouse press sent: #{button}"}
    rescue ex
      Log.error { "Failed to send mouse press: #{ex.message}" }
      {success: false, message: "Error sending mouse press: #{ex.message}"}
    end
  end

  def send_mouse_release(button : String)
    return {success: false, message: "Mouse not available"} unless @mouse_enabled
    return {success: false, message: "No mouse device"} unless @mouse_device

    begin
      @pressed_buttons.delete(button) # Remove from pressed buttons
      HIDMouse.send_mouse_release(@mouse_device, button)
      {success: true, message: "Mouse release sent: #{button}"}
    rescue ex
      Log.error { "Failed to send mouse release: #{ex.message}" }
      {success: false, message: "Error sending mouse release: #{ex.message}"}
    end
  end

  def send_mouse_wheel(wheel_delta : Int32)
    return {success: false, message: "Mouse not available"} unless @mouse_enabled
    return {success: false, message: "No mouse device"} unless @mouse_device

    begin
      HIDMouse.send_mouse_wheel(@mouse_device, wheel_delta)
      {success: true, message: "Mouse wheel sent: #{wheel_delta}"}
    rescue ex
      Log.error { "Failed to send mouse wheel: #{ex.message}" }
      {success: false, message: "Error sending mouse wheel: #{ex.message}"}
    end
  end

  def send_mouse_move_with_buttons(x : Int32, y : Int32, buttons : Array(String))
    return {success: false, message: "Mouse not available"} unless @mouse_enabled
    return {success: false, message: "No mouse device"} unless @mouse_device

    begin
      # Send movement with explicit button state (used for drag operations)
      HIDMouse.send_mouse_move_with_buttons(@mouse_device, x, y, buttons)
      {success: true, message: "Mouse move sent: #{x}, #{y} with explicit buttons: #{buttons}"}
    rescue ex
      Log.error { "Failed to send mouse move with buttons: #{ex.message}" }
      {success: false, message: "Error sending mouse move with buttons: #{ex.message}"}
    end
  end

  # Send absolute mouse move (for absolute pointer device)
  def send_mouse_absolute_move(x : Int32, y : Int32, buttons : Array(String) = [] of String)
    if @mouse_device_absolute.nil? || @mouse_device_absolute.empty?
      return {success: false, message: "Absolute mouse not available"}
    end
    begin
      HIDMouse.send_mouse_absolute_move(@mouse_device_absolute, x, y, buttons)
      {success: true, message: "Absolute mouse move sent: #{x}, #{y} with buttons: #{buttons}"}
    rescue ex
      Log.error { "Failed to send absolute mouse move: #{ex.message}" }
      {success: false, message: "Error sending absolute mouse move: #{ex.message}"}
    end
  end

  def video_device
    @video_device
  end

  def audio_device
    @audio_device
  end

  def width
    @width.to_i32
  end

  def height
    @height.to_i32
  end

  def fps
    @fps
  end

  def status
    video_status = if @video_capture.running?
                     info = @video_capture.device_info
                     {
                       status:           "running",
                       device:           @video_device,
                       resolution:       "#{@width}x#{@height}",
                       fps:              @fps,
                       actual_fps:       @video_capture.actual_fps,
                       stream_url:       "http://#{get_ip_address}:#{get_server_port}/video.mjpg",
                       driver:           info.try(&.[:driver]) || "unknown",
                       card:             info.try(&.[:card]) || "unknown",
                       format:           info.try(&.[:format]) || "unknown",
                       capture_type:     "v4cr",
                       qualities:        available_qualities,
                       selected_quality: selected_quality,
                       jpeg_quality:     @video_jpeg_quality,
                     }
                   else
                     {
                       status:           "stopped",
                       capture_type:     "v4cr",
                       qualities:        available_qualities,
                       selected_quality: selected_quality,
                       jpeg_quality:     @video_jpeg_quality,
                     }
                   end

    keyboard_status = {
      enabled: @keyboard_enabled,
      device:  @keyboard_device,
    }

    mouse_status = {
      enabled:         @mouse_enabled,
      device:          @mouse_device,
      device_absolute: @mouse_device_absolute,
    }

    # Use actual mass storage status from the system
    storage_status = @mass_storage.actual_status

    # Use actual ECM/ethernet status from the system
    ecm_status = HIDComposite.ecm_actual_status

    {
      video:    video_status,
      keyboard: keyboard_status,
      mouse:    mouse_status,
      storage:  storage_status,
      ecm:      ecm_status,
    }
  end

  # Channel-based video client logic removed; direct streaming only

  # Cleanup method to be called on application exit
  def cleanup
    Log.info { "Shutting down and cleaning up KVM resources..." }
    stop_video_stream
    stop_audio_stream
    @mass_storage.cleanup
    HIDComposite.cleanup_all_gadgets
    Log.info { "KVM shutdown cleanup complete." }
  end

  # Static method for a full system cleanup before startup
  def self.perform_system_cleanup
    Log.info { "Performing full system cleanup before startup..." }
    HIDComposite.cleanup_all_gadgets
    Log.info { "System cleanup complete." }
  end

  # ECM/usb0 network interface and DHCP control
  def enable_ecm
    unless @ecm_enabled
      Log.info { "Enabling ECM/ethernet gadget and reinitializing composite device..." }
      @ecm_enabled = true
      setup_hid_devices
    end
    HIDComposite.enable_ecm_interface
    {success: true, message: "ECM/usb0 interface and DHCP enabled"}
  rescue ex
    Log.error { "Failed to enable ECM/usb0: #{ex.message}" }
    {success: false, message: "Error enabling ECM/usb0: #{ex.message}"}
  end

  def disable_ecm
    if @ecm_enabled
      Log.info { "Disabling ECM/ethernet gadget and reinitializing composite device..." }
      @ecm_enabled = false
      setup_hid_devices
    end
    HIDComposite.disable_ecm_interface
    {success: true, message: "ECM/usb0 interface and DHCP disabled"}
  rescue ex
    Log.error { "Failed to disable ECM/usb0: #{ex.message}" }
    {success: false, message: "Error disabling ECM/usb0: #{ex.message}"}
  end

  def ecm_status
    {
      enabled:     @ecm_enabled,
      ifname:      HIDComposite.ethernet_ifname,
      dnsmasq_pid: HIDComposite.dnsmasq_pid,
    }
  end

  # Expose audio_streamer for endpoint use
  def audio_streamer : AudioStreamer
    @audio_streamer
  end

  def video_capture : V4crVideoCapture
    @video_capture
  end

  private def get_server_port
    # Get the port from Kemal config
    Kemal.config.port
  end

  private def get_ip_address
    # Simple way to get local IP
    hostname = `hostname -I`.strip.split.first?
    hostname || "localhost"
  rescue
    "localhost"
  end
end

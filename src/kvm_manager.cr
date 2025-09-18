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
  @disable_mouse : Bool
  @disable_ethernet : Bool
  @disable_mass_storage : Bool
  @video_device : String
  @audio_device : String
  @keyboard_device : String = ""
  @mouse_device : String? = nil          # Relative mouse
  @mouse_device_absolute : String? = nil # Absolute mouse
  @width : UInt32
  @height : UInt32
  @fps : Int32
  @pressed_buttons = Set(String).new
  @pressed_keys = Set(String).new
  @mass_storage : MassStorageManager?
  @video_capture : V4crVideoCapture
  @video_jpeg_quality : Int32 = 100
  @detected_qualities : Array(String)
  @audio_streamer : AudioStreamer

  def initialize(@video_device = "/dev/video1", @audio_device = "hw:1,0", @width = 640_u32, @height = 480_u32, @fps = 30, @video_jpeg_quality = 100, ecm_enabled = false, disable_mouse = false, disable_ethernet = false, disable_mass_storage = false)
    @ecm_enabled = ecm_enabled && !disable_ethernet
    @disable_mouse = disable_mouse
    @disable_ethernet = disable_ethernet
    @disable_mass_storage = disable_mass_storage
    @mass_storage = disable_mass_storage ? nil : MassStorageManager.new
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
    storage_file = @disable_mass_storage ? nil : @mass_storage.try(&.selected_image)
    enable_mass_storage = !@disable_mass_storage && !!storage_file
    enable_mouse = !@disable_mouse

    # Build status string for logging
    status_str = "Setting up USB HID composite gadget (keyboard"
    status_str += " + mouse" if enable_mouse
    status_str += " + mass storage" if enable_mass_storage
    status_str += " + ECM/ethernet" if @ecm_enabled
    status_str += ")..."
    Log.info { status_str }
    Log.info { "Mass storage selected_image: " + (storage_file || "<none>") + ", enable_mass_storage: #{enable_mass_storage}" }

    devices = HIDComposite.setup_usb_composite_gadget(
      enable_mass_storage: enable_mass_storage,
      storage_file: storage_file,
      enable_ecm: @ecm_enabled,
      enable_mouse: enable_mouse
    )

    @keyboard_device = devices[:keyboard]
    @mouse_device = devices[:mouse]?
    @mouse_device_absolute = devices[:mouse_absolute]?
    @keyboard_enabled = File.exists?(@keyboard_device)
    @mouse_enabled = enable_mouse && (mouse_device = @mouse_device) && File.exists?(mouse_device)

    Log.info { "HID keyboard ready: #{@keyboard_device}" }
    if enable_mouse
      Log.info { "HID mouse (relative) ready: #{@mouse_device}" }
      Log.info { "HID mouse (absolute) ready: #{@mouse_device_absolute}" }
    else
      Log.info { "HID mouse disabled by command line option" }
    end

    if enable_mass_storage
      Log.info { "USB mass storage ready: #{storage_file}" }
    else
      Log.info { "USB mass storage disabled by command line option" }
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

  def mouse_disabled?
    @disable_mouse
  end

  def ethernet_disabled?
    @disable_ethernet
  end

  def mass_storage_disabled?
    @disable_mass_storage
  end

  # Safely get mass storage manager for API access
  def mass_storage_manager
    @mass_storage
  end

  def send_keys(keys : Array(String), modifiers : Array(String) = [] of String)
    # Track keys before sending to prevent duplicates
    keys.each do |key|
      if @pressed_keys.includes?(key)
        Log.warn { "Key '#{key}' is already pressed, skipping to prevent duplicate" }
        next
      end
      @pressed_keys.add(key)
    end

    # Remove any keys that were skipped
    active_keys = keys.select { |key| @pressed_keys.includes?(key) }
    return {success: false, message: "No valid keys to send"} if active_keys.empty?

    report = HIDKeyboard.create_keyboard_report(active_keys, modifiers)
    HIDKeyboard.send_keyboard_report(@keyboard_device.to_s, report)

    # Remove keys from pressed state after successful send
    active_keys.each { |key| @pressed_keys.delete(key) }

    {success: true, message: "Keys sent: #{active_keys.join("+")}"}
  rescue ex
    # Clear pressed keys on error
    keys.each { |key| @pressed_keys.delete(key) }
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

  # Emergency method to release all stuck keys
  def release_all_keys
    return {success: false, message: "Keyboard not available"} unless @keyboard_enabled
    return {success: false, message: "No keyboard device"} unless @keyboard_device

    begin
      Log.info { "Releasing all stuck keys (#{@pressed_keys.size} keys)" }

      # Send empty report to release all keys
      empty_report = Bytes.new(8, 0_u8)
      HIDKeyboard.send_keyboard_report(@keyboard_device, empty_report)

      # Clear pressed keys state
      released_keys = @pressed_keys.size
      @pressed_keys.clear

      # Also clear any stuck mouse buttons
      if !@pressed_buttons.empty?
        Log.info { "Releasing stuck mouse buttons (#{@pressed_buttons.size} buttons)" }
        @pressed_buttons.clear
        # Send empty mouse report
        if mouse_device = @mouse_device
          HIDMouse.send_mouse_move_with_buttons(mouse_device, 0, 0, [] of String)
        end
      end

      {success: true, message: "Released #{released_keys} keys and #{@pressed_buttons.size} mouse buttons"}
    rescue ex
      Log.error { "Failed to release keys: #{ex.message}" }
      {success: false, message: "Error releasing keys: #{ex.message}"}
    end
  end

  def send_mouse_click(button : String)
    return {success: false, message: "Mouse not available"} unless @mouse_enabled
    return {success: false, message: "No mouse device"} unless @mouse_device

    begin
      if mouse_device = @mouse_device
        HIDMouse.send_mouse_click(mouse_device, button)
        {success: true, message: "Mouse click sent: #{button}"}
      else
        {success: false, message: "Mouse device not available"}
      end
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
      if mouse_device = @mouse_device
        HIDMouse.send_mouse_move_with_buttons(mouse_device, x, y, @pressed_buttons.to_a)
        {success: true, message: "Mouse move sent: #{x}, #{y} with buttons: #{@pressed_buttons.to_a}"}
      else
        {success: false, message: "Mouse device not available"}
      end
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
      if mouse_device = @mouse_device
        HIDMouse.send_mouse_press(mouse_device, button)
        {success: true, message: "Mouse press sent: #{button}"}
      else
        {success: false, message: "Mouse device not available"}
      end
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
      if mouse_device = @mouse_device
        HIDMouse.send_mouse_release(mouse_device, button)
        {success: true, message: "Mouse release sent: #{button}"}
      else
        {success: false, message: "Mouse device not available"}
      end
    rescue ex
      Log.error { "Failed to send mouse release: #{ex.message}" }
      {success: false, message: "Error sending mouse release: #{ex.message}"}
    end
  end

  def send_mouse_wheel(wheel_delta : Int32)
    return {success: false, message: "Mouse not available"} unless @mouse_enabled
    return {success: false, message: "No mouse device"} unless @mouse_device

    begin
      if mouse_device = @mouse_device
        HIDMouse.send_mouse_wheel(mouse_device, wheel_delta)
        {success: true, message: "Mouse wheel sent: #{wheel_delta}"}
      else
        {success: false, message: "Mouse device not available"}
      end
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
      if mouse_device = @mouse_device
        HIDMouse.send_mouse_move_with_buttons(mouse_device, x, y, buttons)
        {success: true, message: "Mouse move sent: #{x}, #{y} with explicit buttons: #{buttons}"}
      else
        {success: false, message: "Mouse device not available"}
      end
    rescue ex
      Log.error { "Failed to send mouse move with buttons: #{ex.message}" }
      {success: false, message: "Error sending mouse move with buttons: #{ex.message}"}
    end
  end

  # Send absolute mouse move (for absolute pointer device)
  def send_mouse_absolute_move(x : Int32, y : Int32, buttons : Array(String) = [] of String)
    if mouse_device_absolute = @mouse_device_absolute
      begin
        HIDMouse.send_mouse_absolute_move(mouse_device_absolute, x, y, buttons)
        {success: true, message: "Absolute mouse move sent: #{x}, #{y} with buttons: #{buttons}"}
      rescue ex
        Log.error { "Failed to send absolute mouse move: #{ex.message}" }
        {success: false, message: "Error sending absolute mouse move: #{ex.message}"}
      end
    else
      {success: false, message: "Absolute mouse not available"}
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
    device_available = video_device_available?
    device_accessible = @video_capture.device_available?

    video_status = if @video_capture.running?
                     info = @video_capture.device_info
                     {
                       status:            "running",
                       device:            @video_device,
                       device_available:  device_available,
                       device_accessible: device_accessible,
                       resolution:        "#{@width}x#{@height}",
                       fps:               @fps,
                       actual_fps:        @video_capture.actual_fps,
                       stream_url:        "http://#{get_ip_address}:#{get_server_port}/video.mjpg",
                       driver:            info.try(&.[:driver]) || "unknown",
                       card:              info.try(&.[:card]) || "unknown",
                       format:            info.try(&.[:format]) || "unknown",
                       capture_type:      "v4cr",
                       qualities:         available_qualities,
                       selected_quality:  selected_quality,
                       jpeg_quality:      @video_jpeg_quality,
                     }
                   else
                     {
                       status:            "stopped",
                       device:            @video_device,
                       device_available:  device_available,
                       device_accessible: device_accessible,
                       capture_type:      "v4cr",
                       qualities:         available_qualities,
                       selected_quality:  selected_quality,
                       jpeg_quality:      @video_jpeg_quality,
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
    storage_status = if @disable_mass_storage
                       {attached: false, image: nil, readonly: false}
                     elsif mass_storage = @mass_storage
                       mass_storage.actual_status
                     else
                       {attached: false, image: nil, readonly: false}
                     end

    # Use actual ECM/ethernet status from the system
    ecm_status = HIDComposite.ecm_actual_status

    {
      video:    video_status,
      keyboard: keyboard_status,
      mouse:    mouse_status,
      storage:  storage_status,
      ecm:      ecm_status,
      disabled: {
        mouse:        @disable_mouse,
        ethernet:     @disable_ethernet,
        mass_storage: @disable_mass_storage,
      },
    }
  end

  # Channel-based video client logic removed; direct streaming only

  # Cleanup method to be called on application exit
  def cleanup
    Log.info { "Shutting down and cleaning up KVM resources..." }
    stop_video_stream
    stop_audio_stream
    @mass_storage.try(&.cleanup)
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

  # Handle video device re-detection if current device fails
  def handle_video_device_failure : Bool
    Log.warn { "Handling video device failure for #{@video_device}" }

    # Try to redetect and switch the video capture device
    if @video_capture.redetect_and_switch_device
      # Update our stored device path to match the new one
      @video_device = @video_capture.device_path
      Log.info { "Successfully switched video device to #{@video_device}" }
      true
    else
      Log.error { "Failed to find alternative video device" }
      false
    end
  end

  # Check if current video device is available
  def video_device_available? : Bool
    File.exists?(@video_device)
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

require "./keyboard"
require "./mouse"
require "./composite"
require "./mass_storage_manager"
require "./video_capture"
require "kemal"

# Updated KVM manager using V4cr for video capture instead of FFmpeg
class KVMManagerV4cr
  Log = ::Log.for(self)

  @keyboard_enabled = false
  @mouse_enabled = false
  @ecm_enabled : Bool
  @video_device : String
  @audio_device : String
  @keyboard_device : String = ""
  @mouse_device : String = ""
  @width : UInt32
  @height : UInt32
  @fps : Int32
  @pressed_buttons = Set(String).new
  @mass_storage : MassStorageManager
  @video_capture : V4crVideoCapture


  def initialize(@video_device = "/dev/video1", @audio_device = "hw:1,0", @width = 640_u32, @height = 480_u32, @fps = 30, ecm_enabled = false)
    @ecm_enabled = ecm_enabled
    @mass_storage = MassStorageManager.new
    @video_capture = V4crVideoCapture.new(@video_device, @width, @height, @fps)
    setup_hid_devices
    start_video_stream # Start video automatically
  end

  def setup_hid_devices
    Log.info { "Setting up USB HID composite gadget (keyboard + mouse + mass storage#{@ecm_enabled ? " + ECM/ethernet" : ""})..." }

    storage_file = @mass_storage.selected_image
    enable_mass_storage = !!storage_file

    devices = HIDComposite.setup_usb_composite_gadget(
      enable_mass_storage: enable_mass_storage,
      storage_file: storage_file,
      enable_ecm: @ecm_enabled
    )

    @keyboard_device = devices[:keyboard]
    @mouse_device = devices[:mouse]
    @keyboard_enabled = File.exists?(@keyboard_device)
    @mouse_enabled = File.exists?(@mouse_device)

    Log.info { "HID keyboard ready: #{@keyboard_device}" }
    Log.info { "HID mouse ready: #{@mouse_device}" }

    if enable_mass_storage
      Log.info { "USB mass storage ready: #{storage_file}" }
    else
      Log.info { "No USB mass storage image attached" }
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
                       status:       "running",
                       device:       @video_device,
                       resolution:   "#{@width}x#{@height}",
                       fps:          @fps,
                       actual_fps:   @video_capture.actual_fps,
                       stream_url:   "http://#{get_ip_address}:#{get_server_port}/video.mjpg",
                       driver:       info.try(&.[:driver]) || "unknown",
                       card:         info.try(&.[:card]) || "unknown",
                       format:       info.try(&.[:format]) || "unknown",
                       clients:      nil, # client_count removed, always nil
                       capture_type: "v4cr",
                     }
                   else
                     {
                       status:       "stopped",
                       capture_type: "v4cr",
                     }
                   end

    keyboard_status = {
      enabled: @keyboard_enabled,
      device:  @keyboard_device,
    }

    mouse_status = {
      enabled: @mouse_enabled,
      device:  @mouse_device,
    }

    storage_status = @mass_storage.status

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

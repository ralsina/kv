require "./keyboard"
require "./mouse"
require "./composite"
require "./mass_storage_manager"
require "kemal"

# Integrated KVM manager - handles video, keyboard, and mouse
class KVMManager
  Log = ::Log.for(self)

  @video_running = false
  @keyboard_enabled = false
  @mouse_enabled = false
  @video_device : String
  @keyboard_device : String = ""
  @mouse_device : String = ""
  @width : Int32
  @height : Int32
  @fps : Int32
  @quality : Int32
  @pressed_buttons = Set(String).new
  @mass_storage : MassStorageManager

  # For robust ffmpeg management
  @ffmpeg_process : Process?
  @stop_ffmpeg = Channel(Nil).new
  @clients = [] of Channel(Bytes)
  @clients_mutex = Mutex.new

  def initialize(@video_device = "/dev/video1", @width = 640, @height = 480, @fps = 30, @quality = 80)
    @mass_storage = MassStorageManager.new # No arguments needed
    setup_hid_devices
    start_video_stream # Start video automatically
  end

  def setup_hid_devices
    Log.info { "Setting up USB HID composite gadget (keyboard + mouse + mass storage)..." }

    storage_file = @mass_storage.selected_image
    enable_mass_storage = !!storage_file

    devices = HIDComposite.setup_usb_composite_gadget(
      enable_mass_storage: enable_mass_storage,
      storage_file: storage_file
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
    return if @video_running
    @video_running = true
    Log.info { "Starting robust video stream loop..." }

    spawn do
      loop do
        # Check if we should stop (non-blocking)
        select
        when @stop_ffmpeg.receive
          @video_running = false
          Log.warn { "Video stream loop stopped." }
          break
        else
          # Continue with ffmpeg startup
        end

        command = [
          "ffmpeg",
          "-f", "v4l2",
          "-input_format", "mjpeg",
          "-video_size", "#{@width}x#{@height}",
          "-framerate", @fps.to_s,
          "-i", @video_device,
          "-c:v", "mjpeg",
          "-q:v", ((100 - @quality) / 3.125).round.to_i.to_s,
          "-fflags", "nobuffer",
          "-f", "mjpeg",
          "-",
        ]

        begin
          @ffmpeg_process = Process.new(
            command[0], command[1..-1],
            output: Process::Redirect::Pipe,
            error: Process::Redirect::Pipe
          )

          if @ffmpeg_process.nil?
            raise "FFmpeg process could not be created."
          else
            process : Process = @ffmpeg_process.as(Process)
          end
          Log.debug { "FFmpeg process started with PID: #{process.pid}" }
          Log.debug { "FFmpeg command: #{command.join(" ")}" }

          # Read from ffmpeg's stdout and extract only the latest complete JPEG frame
          if ffmpeg_output = process.output
            read_buffer = Bytes.new(4096)
            frame_buffer = Bytes.new(0)
            while @video_running
              bytes_read = ffmpeg_output.read(read_buffer)
              if bytes_read == 0
                Log.debug { "FFmpeg stdout pipe closed." }
                break
              end
              # Append new data to frame_buffer
              frame_buffer += read_buffer[0, bytes_read]

              # Extract all complete JPEG frames, but only send the latest one
              offset = 0
              latest_frame = nil
              while offset < frame_buffer.size
                # Find SOI marker
                soi = frame_buffer.index(0xFF_u8, offset)
                if soi && soi + 1 < frame_buffer.size && frame_buffer[soi + 1] == 0xD8_u8
                  # Found SOI, now look for EOI
                  eoi = soi + 2
                  while eoi + 1 < frame_buffer.size
                    if frame_buffer[eoi] == 0xFF_u8 && frame_buffer[eoi + 1] == 0xD9_u8
                      # Found EOI, extract frame
                      jpeg_end = eoi + 2
                      latest_frame = frame_buffer[soi, jpeg_end - soi]
                      offset = jpeg_end
                      break
                    end
                    eoi += 1
                  end
                  # If EOI not found, wait for more data
                  if eoi + 1 >= frame_buffer.size
                    break
                  end
                else
                  # No SOI found, discard processed bytes
                  break
                end
              end
              # Remove processed bytes from frame_buffer
              if offset > 0
                frame_buffer = frame_buffer[offset..-1]
              end
              # Only broadcast the latest complete frame (skip intermediates)
              if latest_frame
                broadcast(latest_frame)
              end
            end
          end
        rescue ex
          Log.error { "FFmpeg process failed: #{ex.message}" }
          if @ffmpeg_process
            if error_io = @ffmpeg_process.as(Process).error
              error_output = error_io.gets_to_end
              Log.error { "FFmpeg stderr: #{error_output}" }
            end
          end
        ensure
          # Make sure process is terminated
          if @ffmpeg_process
            p = @ffmpeg_process.as(Process)
            p.signal(Signal::TERM) if p.exists?
            p.wait
            @ffmpeg_process = nil
          end

          # If the loop is still supposed to be running, wait before restarting
          if @video_running
            Log.info { "FFmpeg process exited. Restarting in 2 seconds..." }
            sleep 2.seconds
          end
        end
      end
    end
    true
  end

  def stop_video_stream
    return unless @video_running
    @video_running = false
    @stop_ffmpeg.send(nil) # Blocking send to signal stop

    # Terminate the process if it's running
    if process = @ffmpeg_process
      process.signal(Signal::TERM) if process.exists?
      @ffmpeg_process = nil
    end

    # Close all client channels
    @clients_mutex.synchronize do
      @clients.each(&.close)
      @clients.clear
    end

    Log.warn { "Video stream disabled" }
  end

  def video_running?
    @video_running
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

  def width
    @width
  end

  def height
    @height
  end

  def fps
    @fps
  end

  def quality
    @quality
  end

  def set_quality(new_quality : Int32)
    @quality = new_quality.clamp(1, 100)
  end

  def status
    video_status = if @video_running
                     {
                       status:     "running",
                       device:     @video_device,
                       resolution: "#{@width}x#{@height}",
                       fps:        @fps,
                       stream_url: "http://#{get_ip_address}:#{get_server_port}/video.mjpg",
                     }
                   else
                     {
                       status: "stopped",
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

    {
      video:    video_status,
      keyboard: keyboard_status,
      mouse:    mouse_status,
      storage:  storage_status,
    }
  end

  # Register a new client to receive video stream data
  def register_client(client_channel : Channel(Bytes))
    @clients_mutex.synchronize do
      @clients << client_channel
    end
  end

  # Unregister a client
  def unregister_client(client_channel : Channel(Bytes))
    @clients_mutex.synchronize do
      @clients.delete(client_channel)
    end
  end

  # Broadcast data to all connected clients
  private def broadcast(data : Bytes)
    clients_to_remove = [] of Channel(Bytes)
    @clients_mutex.synchronize do
      @clients.each do |client|
        begin
          client.send(data) # Blocking send, but we handle closed channels
        rescue Channel::ClosedError
          clients_to_remove << client
        end
      end
      @clients.reject! { |client| clients_to_remove.includes?(client) }
    end
  end

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

require "v4cr"
require "log"
require "pluto"
require "pluto/format/jpeg"

# V4cr-based video capture module to replace FFmpeg
class V4crVideoCapture
  Log = ::Log.for(self)

  @device : V4cr::Device
  @streaming_fiber : Fiber?
  @running = false
  @stop_channel = Channel(Nil).new
  @frame_count : Int32 = 0
  @actual_fps : Float64 = 0.0
  @last_fps_time : Time::Span = Time.monotonic
  @quality : Int32 = 100

  MJPEG_BOUNDARY = "--mjpegboundary"

  # Thread-safe list of client channels
  @clients_mutex = Mutex.new
  @clients = [] of Channel(Bytes)

  def initialize(@device_path : String = "/dev/video0", @width : UInt32 = 640_u32, @height : UInt32 = 480_u32, @fps : Int32 = 30, @jpeg_quality : Int32 = 100)
    if @device_path.empty?
      Log.warn { "Video device path is empty - video capture disabled" }
      @device = V4cr::Device.new("/dev/null") # Use null device as placeholder
    else
      @device = V4cr::Device.new(@device_path)
    end
  end

  # Allow changing FPS at runtime
  def fps=(fps : Int32)
    @fps = fps
    if @device.open?
      begin
        @device.framerate = fps.to_u32
        Log.info { "Set device FPS to #{fps}" }
      rescue ex
        Log.warn { "Failed to set device FPS to #{fps}: #{ex.message}" }
      end
    end
  end

  # Allow changing JPEG quality at runtime
  def jpeg_quality=(quality : Int32)
    @jpeg_quality = quality
    if @device.open?
      begin
        @device.jpeg_quality = quality
        Log.info { "Set device JPEG quality to #{quality}" }
        @quality = quality # Set internal quality for re-encoding only if device setting succeeds
      rescue ex
        Log.warn { "Failed to set device JPEG quality to #{quality}: #{ex.message}. Assuming 100% quality and skipping re-encoding." }
        @quality = 100 # Assume 100% quality if device setting fails, to skip re-encoding
      end
    else
      @quality = quality # If device not open, still set internal quality for re-encoding
    end
  end

  # Initialize and configure the V4L2 device
  def initialize_device : Bool
    return false unless File.exists?(@device_path)

    begin
      # Ensure device is closed before reopening
      cleanup
      @device = V4cr::Device.new(@device_path)
      device = @device
      device.open

      capability = device.query_capability
      unless capability.video_capture?
        Log.error { "Device #{@device_path} does not support video capture" }
        return false
      end

      begin
        device.set_format(@width, @height, V4cr::LibV4L2::V4L2_PIX_FMT_MJPG)
        fmt = device.format
        @width = fmt.width || @width
        @height = fmt.height || @height
        Log.info { "Device #{@device_path} configured for MJPEG #{fmt.width}x#{fmt.height} (actual format: #{fmt.format_name})" }

        # Set initial FPS and JPEG quality
        self.fps = @fps
        self.jpeg_quality = @jpeg_quality

        true
      rescue e
        Log.error { "Failed to set MJPEG format or device parameters: #{e.message}" }
        false
      end
    rescue e
      Log.error { "Failed to initialize device #{@device_path}: #{e.message}" }
      false
    end
  end

  # Start video streaming
  def start_streaming : Bool
    return false if @running
    return false unless initialize_device

    device = @device
    begin
      device.request_buffers(4)
      device.buffer_manager.each do |buffer|
        device.queue_buffer(buffer)
      end
      device.start_streaming
      @running = true
      start_streaming_fiber
      Log.info { "V4cr video streaming started on #{@device_path}" }
      true
    rescue e
      Log.error { "Failed to start streaming: #{e.message}" }
      cleanup
      false
    end
  end

  # Stop video streaming
  def stop_streaming
    return unless @running

    # Signal streaming fiber to stop
    @stop_channel.send(nil)

    # Wait for the fiber to finish by polling the @running flag
    while @running
      sleep(10.milliseconds)
    end

    @streaming_fiber = nil

    cleanup
    Log.info { "V4cr video streaming stopped" }
  end

  def running?
    @running
  end

  def device_info
    return nil unless @device.open?
    capability = @device.query_capability
    format = @device.format
    {
      device: @device_path,
      card:   capability.card,
      driver: capability.driver,
      format: format.format_name,
      width:  format.width,
      height: format.height,
    }
  end

  def add_client(channel : Channel(Bytes))
    @clients_mutex.synchronize { @clients.<< channel }
  end

  def remove_client(channel : Channel(Bytes))
    @clients_mutex.synchronize { @clients.delete(channel) }
    channel.close rescue nil
  end

  def client_count : Int32
    @clients_mutex.synchronize { @clients.size }
  end

  def stream_to_http_response(response)
    channel = Channel(Bytes).new(5) # Buffer 5 frames
    add_client(channel)
    Log.info { "MJPEG client connected. Total clients: #{@clients_mutex.synchronize { @clients.size }} " }

    begin
      loop do
        frame = channel.receive
        response.write(MJPEG_BOUNDARY.to_slice)
        response.write("\r\n".to_slice)
        response.write("Content-Type: image/jpeg\r\n".to_slice)
        response.write("Content-Length: #{frame.size}\r\n\r\n".to_slice)
        response.write(frame)
        response.write("\r\n".to_slice)
        response.flush
      end
    rescue ex : Channel::ClosedError
      Log.info { "MJPEG client channel closed." }
    rescue ex
      Log.error(exception: ex) { "MJPEG client streaming error" }
    ensure
      remove_client(channel)
      Log.info { "MJPEG client disconnected. Total clients: #{@clients_mutex.synchronize { @clients.size }}" }
    end
  end

  def actual_fps : Float64
    @actual_fps
  end

  def device_path : String
    @device_path
  end

  # Check if current device is still available
  def device_available? : Bool
    File.exists?(@device_path) && @device.open?
  end

  # Attempt to find and switch to an available video device
  def redetect_and_switch_device : Bool
    Log.warn { "Current video device #{@device_path} is no longer available, attempting re-detection..." }

    # First, clean up the current device
    cleanup

    # Try to find a new available device
    0.upto(9) do |i|
      candidate_path = "/dev/video#{i}"
      next unless File.exists?(candidate_path)
      next if candidate_path == @device_path # Skip the failed device

      Log.info { "Testing video device #{candidate_path}..." }

      # Test if this device works
      if test_device_compatibility(candidate_path)
        Log.info { "Successfully switched from #{@device_path} to #{candidate_path}" }
        @device_path = candidate_path
        @device = V4cr::Device.new(@device_path)
        return true
      end
    end

    Log.error { "No alternative video devices found that are compatible" }
    false
  end

  # Test if a device is compatible with our requirements
  private def test_device_compatibility(device_path : String) : Bool
    test_device = V4cr::Device.new(device_path)
    test_device.open

    capability = test_device.query_capability
    unless capability.video_capture?
      test_device.close
      return false
    end

    # Try to set the format we need
    test_device.set_format(@width, @height, V4cr::LibV4L2::V4L2_PIX_FMT_MJPG)

    test_device.close
    Log.debug { "Device #{device_path} is compatible" }
    true
  rescue e
    Log.debug { "Device #{device_path} is not compatible: #{e.message}" }
    false
  end

  private def reencode_frame(frame_data : Bytes) : Bytes
    return frame_data if @quality == 100

    begin
      io = IO::Memory.new(frame_data)
      image = Pluto::ImageRGBA.from_jpeg(io)

      output_io = IO::Memory.new
      image.to_jpeg(output_io, @quality)
      output_io.rewind
      output_io.gets_to_end.to_slice
    rescue ex
      Log.error(exception: ex) { "Failed to re-encode frame" }
      frame_data
    end
  end

  private def broadcast_frame(frame_data : Bytes)
    reencoded_data = reencode_frame(frame_data)
    @clients_mutex.synchronize do
      # We dup the data because each channel receive might happen at a different time.
      # This prevents one fiber from seeing data that another fiber has already modified
      # if we were passing a mutable buffer. Slices are structs, but the underlying
      # pointer could be an issue if not duped.
      @clients.each do |client|
        begin
          # Non-blocking send: skip if channel is full
          select
          when client.send(reencoded_data.dup)
            # sent immediately
          else
            # channel full, skip this client for this frame
            Log.debug { "[VIDEO] Skipping video frame for slow client" }
          end
        rescue ex
          Log.warn { "[VIDEO] Failed to send video frame to client: #{ex.message}" }
        end
      end
    end
  end

  private def start_streaming_fiber
    @streaming_fiber = spawn do
      device = @device
      consecutive_errors = 0
      last_device_check = Time.monotonic

      loop do
        select
        when @stop_channel.receive?
          break
        else
          # continue
        end

        begin
          buffer = device.dequeue_buffer
          data = buffer.read_data
          size = data.size
          valid_jpeg = size > 1000 && data[0] == 0xFF && data[1] == 0xD8 && data[size - 2] == 0xFF && data[size - 1] == 0xD9

          now = Time.monotonic
          if valid_jpeg
            broadcast_frame(data)
            @frame_count += 1
            consecutive_errors = 0 # Reset error counter on successful frame
          else
            Log.debug { "Skipping invalid JPEG frame (size: #{size})" }
          end

          device.queue_buffer(buffer)

          if (now - @last_fps_time) >= 1.second
            elapsed_seconds = (now - @last_fps_time).total_seconds
            if elapsed_seconds > 0
              @actual_fps = @frame_count / elapsed_seconds
            end
            @frame_count = 0
            @last_fps_time = now
          end

          Fiber.yield
        rescue ex : V4cr::Error
          consecutive_errors += 1
          Log.error(exception: ex) { "V4L2 error in streaming fiber (error ##{consecutive_errors})" }

          # If we have multiple consecutive errors, check if device is still available
          if consecutive_errors >= 3
            now = Time.monotonic
            # Only check device availability every 5 seconds to avoid excessive checks
            if (now - last_device_check) >= 5.seconds
              last_device_check = now
              unless device_available?
                Log.warn { "Video device appears to be unavailable, attempting re-detection..." }
                if redetect_and_switch_device
                  Log.info { "Successfully switched to new video device, restarting streaming..." }
                  # Restart streaming with new device
                  if initialize_device
                    device = @device
                    begin
                      device.request_buffers(4)
                      device.buffer_manager.each do |buf|
                        device.queue_buffer(buf)
                      end
                      device.start_streaming
                      consecutive_errors = 0
                      Log.info { "Streaming restarted successfully with new device" }
                      next
                    rescue ex
                      Log.error { "Failed to restart streaming with new device: #{ex.message}" }
                    end
                  end
                else
                  Log.error { "Failed to find alternative video device, stopping streaming" }
                  break
                end
              end
            end
          end

          sleep 1.second
        rescue ex
          Log.error(exception: ex) { "Unknown error in streaming fiber" }
          consecutive_errors += 1
          if consecutive_errors >= 10
            Log.error { "Too many consecutive errors, stopping streaming fiber" }
            break
          end
          sleep 1.second
        end
      end
      Log.info { "Streaming fiber stopped." }
      # Close all client channels when the fiber stops
      @clients_mutex.synchronize do
        @clients.each(&.close)
        @clients.clear
      end
      @running = false
    end
  end

  private def cleanup
    @device.stop_streaming rescue nil
    @device.close rescue nil
  end

  def finalize
    cleanup
  end
end

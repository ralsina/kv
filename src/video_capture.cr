require "v4cr"
require "log"

# V4cr-based video capture module to replace FFmpeg
class V4crVideoCapture
  Log = ::Log.for(self)

  @device : V4cr::Device = V4cr::Device.new("/dev/video0/")
  @streaming_fiber : Fiber?
  @running = false
  @stop_channel = Channel(Nil).new

  MJPEG_BOUNDARY = "mjpegboundary"

  # All channel-based video client logic removed; direct streaming only
  def initialize(@device_path : String = "/dev/video0", @width : UInt32 = 640_u32, @height : UInt32 = 480_u32)
  end

  # Initialize and configure the V4L2 device
  def initialize_device : Bool
    return false unless File.exists?(@device_path)

    begin
      @device = V4cr::Device.new(@device_path)
      device = @device
      device.open

      # JPEG quality control not supported; parameter removed

      # Check if device supports video capture
      capability = device.query_capability
      unless capability.video_capture?
        Log.error { "Device #{@device_path} does not support video capture" }
        return false
      end

      # Try to set MJPEG format with requested resolution, fallback to common ones if needed
      begin
        device.set_format(@width, @height, V4cr::LibV4L2::V4L2_PIX_FMT_MJPEG)
        fmt = device.format
        @width = fmt.width || @width
        @height = fmt.height || @height
        Log.info { "Device #{@device_path} configured for MJPEG #{fmt.width}x#{fmt.height} (actual format: #{fmt.format_name})" }
        true
      rescue e
        Log.error { "Failed to set MJPEG format: #{e.message}" }
        # Try fallback resolutions (match v4cr example order)
        fallback_resolutions = [
          {1920_u32, 1080_u32},
          {320_u32, 240_u32},
          {640_u32, 480_u32},
          {800_u32, 600_u32},
          {1024_u32, 768_u32},
        ]

        fallback_resolutions.each do |width, height|
          begin
            device.set_format(width, height, V4cr::LibV4L2::V4L2_PIX_FMT_MJPEG)
            fmt = device.format
            @width = fmt.width || @width
            @height = fmt.height || @height
            Log.info { "Device #{@device_path} configured for MJPEG #{fmt.width}x#{fmt.height} (fallback, actual format: #{fmt.format_name})" }
            return true
          rescue
            # Try next resolution
          end
        end

        Log.error { "Device #{@device_path} doesn't support MJPEG format at any tested resolution" }
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
      # Request buffers for streaming (use 4 for better performance, per v4cr example)
      device.request_buffers(4)

      # Log buffer lengths for debugging
      device.buffer_manager.each_with_index do |buffer, idx|
        Log.debug { "Buffer \\##{idx} length: \\#{buffer.length}" }
      end

      # Queue all buffers
      device.buffer_manager.each do |buffer|
        device.queue_buffer(buffer)
      end

      # Start streaming
      device.start_streaming
      @running = true

      # Wait a bit before starting the streaming fiber to avoid initial invalid frames
      sleep(100.milliseconds)

      # Start streaming fiber
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
    @running = false

    # Signal streaming fiber to stop
    spawn { @stop_channel.send(nil) }

    # Wait a bit for streaming fiber to finish
    sleep(100.milliseconds)
    @streaming_fiber = nil

    cleanup
    Log.info { "V4cr video streaming stopped" }
  end

  # Check if streaming is running
  def running?
    @running
  end

  # Get device information
  def device_info
    return nil unless @device

    device = @device
    capability = device.query_capability
    format = device.format

    {
      device: @device_path,
      card:   capability.card,
      driver: capability.driver,
      format: format.format_name,
      width:  format.width,
      height: format.height,
    }
  end

  # Stream MJPEG frames directly to an HTTP response (blocking, one client per call)
  def stream_to_http_response(response)
    device = @device
    boundary = "--mjpegboundary"
    frame_interval = 33.milliseconds
    last_write_time = Time.monotonic
    skipped = 0
    begin
      loop do
        buffer = device.dequeue_buffer
        data = buffer.read_data
        size = data.size
        valid_jpeg = size >= 1000 &&
                     data[0] == 0xFF && data[1] == 0xD8 &&
                     data[-2] == 0xFF && data[-1] == 0xD9

        now = Time.monotonic
        elapsed = now - last_write_time
        if elapsed < frame_interval
          # We're ahead of schedule, send frame
          if valid_jpeg
            response.write(boundary.to_slice)
            response.write("\r\n".to_slice)
            response.write("Content-Type: image/jpeg\r\n".to_slice)
            response.write("Content-Length: #{size}\r\n\r\n".to_slice)
            response.write(data)
            response.write("\r\n".to_slice)
            response.flush
          end
          skipped = 0
        else
          # We're behind, skip this frame
          skipped += 1
          if skipped == 1 || skipped % 10 == 0
            Log.debug { "MJPEG: Skipping frame(s) to catch up (#{skipped} skipped, write took #{elapsed.total_milliseconds.round(1)}ms)" }
          end
        end
        last_write_time = now
        device.queue_buffer(buffer)
        # No sleep: frame pacing is now dynamic
      end
    rescue e
      Log.info { "Client disconnected or error: #{e.message}" }
    end
  end

  private def start_streaming_fiber
    @streaming_fiber = spawn do
      device = @device
      frame_count = 0
      saved_invalid = false
      loop do
        # Check for stop signal (non-blocking)
        select
        when @stop_channel.receive
          Log.debug { "Streaming fiber received stop signal" }
          break
        else
          # Continue streaming
        end

        begin
          # Dequeue a frame buffer

          buffer = device.dequeue_buffer
          frame_count += 1
          # Always use buffer.read_data for the actual frame data
          data = buffer.read_data
          size = data.size
          valid_jpeg = size >= 1000 &&
                       data[0] == 0xFF && data[1] == 0xD8 &&
                       data[-2] == 0xFF && data[-1] == 0xD9

          if frame_count <= 10 || !valid_jpeg
            Log.debug { "[Frame #{frame_count}] size=#{size} valid_jpeg=#{valid_jpeg}" }
          end

          if valid_jpeg
            # Broadcast frame to all clients
            broadcast_frame(data)
          else
            Log.debug { "Received invalid JPEG frame, skipping (frame #{frame_count}, size #{size})" }
          end

          # Always re-queue the buffer
          device.queue_buffer(buffer)

          # Control frame rate (~30 FPS)
          sleep(33.milliseconds)
        rescue e
          Log.error { "Error in streaming fiber: #{e.message}" }
          break unless @running
          sleep(20.milliseconds) # Shorter sleep for smoother recovery
        end
      end

      Log.debug { "Streaming fiber exited" }
    end
  end

  # No-op: broadcast_frame and client logic removed (direct streaming only)
  private def broadcast_frame(frame_data : Bytes)
    # No-op
  end

  private def cleanup
    @device.stop_streaming rescue nil
    @device.close rescue nil
  end

  # Cleanup on object destruction
  def finalize
    cleanup
  end
end

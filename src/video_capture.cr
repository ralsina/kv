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
  @fps : Int32
  @frame_count : Int32 = 0
  @actual_fps : Float64 = 0.0
  @last_fps_time : Time::Span = Time.monotonic
  @quality : Int32 = 100

  MJPEG_BOUNDARY = "--mjpegboundary"

  # Thread-safe list of client channels
  @clients_mutex = Mutex.new
  @clients = [] of Channel(Bytes)

  def initialize(@device_path : String = "/dev/video0", @width : UInt32 = 640_u32, @height : UInt32 = 480_u32, @fps : Int32 = 30)
    @device = V4cr::Device.new(@device_path)
  end

  # Initialize and configure the V4L2 device
  def initialize_device : Bool
    return false unless File.exists?(@device_path)

    begin
      device = @device
      device.open

      capability = device.query_capability
      unless capability.video_capture?
        Log.error { "Device #{@device_path} does not support video capture" }
        return false
      end

      begin
        device.set_format(@width, @height, V4cr::LibV4L2::V4L2_PIX_FMT_MJPEG)
        fmt = device.format
        @width = fmt.width || @width
        @height = fmt.height || @height
        Log.info { "Device #{@device_path} configured for MJPEG #{fmt.width}x#{fmt.height} (actual format: #{fmt.format_name})" }
        true
      rescue e
        Log.error { "Failed to set MJPEG format: #{e.message}" }
        # Fallback logic can be added here if needed
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

  def quality=(new_quality : Int32)
    @quality = new_quality
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
        client.send(reencoded_data.dup)
      end
    end
  end

  private def start_streaming_fiber
    @streaming_fiber = spawn do
      device = @device
      frame_sleep = (1000 / @fps).milliseconds
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

          if valid_jpeg
            broadcast_frame(data)
            @frame_count += 1
          else
            Log.debug { "Skipping invalid JPEG frame (size: #{size})" }
          end

          device.queue_buffer(buffer)

          now = Time.monotonic
          if (now - @last_fps_time) >= 1.second
            elapsed_seconds = (now - @last_fps_time).total_seconds
            if elapsed_seconds > 0
              @actual_fps = @frame_count / elapsed_seconds
            end
            @frame_count = 0
            @last_fps_time = now
          end

          sleep frame_sleep
        rescue ex : V4cr::Error
          Log.error(exception: ex) { "V4L2 error in streaming fiber" }
          sleep 1.second
        rescue ex
          Log.error(exception: ex) { "Unknown error in streaming fiber" }
          break
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

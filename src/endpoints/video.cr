# Video and audio streaming endpoints
require "../kvm_manager"
require "../alsa_pcm"
require "opus"
require "../ogg_opus_muxer"

get "/audio.ogg" do |env|
  env.response.content_type = "audio/ogg"
  env.response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
  env.response.headers["Pragma"] = "no-cache"
  env.response.headers["Expires"] = "0"
  env.response.headers["Connection"] = "keep-alive"
  env.response.headers["Access-Control-Allow-Origin"] = "*"

  pipe_reader, pipe_writer = IO.pipe

  spawn do
    mux = nil
    pcm = nil

    begin
      sample_rate = 48000
      channels = 2
      frame_size = 960 # 20ms at 48kHz

      pcm = AlsaPcmCapture.new(GlobalKVM.manager.audio_device, channels, sample_rate)
      encoder = Opus::Encoder.new(sample_rate, frame_size, channels)
      pcm_buffer = Bytes.new(frame_size * channels * 2) # 16-bit samples

      serial = Random.rand(Int32::MAX)
      mux = OggOpusMuxer.new(pipe_writer, serial, sample_rate, channels)

      granulepos = 0_i64
      chunk_duration = 20.milliseconds
      loop do
        loop_start_time = Time.monotonic

        frames = pcm.read(pcm_buffer, frame_size)
        if frames <= 0
          STDERR.puts "PCM read failed or stream ended"
          break
        end

        opus_data = encoder.encode(pcm_buffer)
        if opus_data.empty?
          STDERR.puts "Opus encoding failed"
          break
        end

        granulepos += frames
        mux.write_packet(opus_data, granulepos)

        # Pace the loop to send audio in real-time to avoid client-side buffer bloat and lag.
        # This also yields to other fibers.
        elapsed = Time.monotonic - loop_start_time
        sleep_duration = chunk_duration - elapsed
        if sleep_duration > Time::Span.zero
          sleep sleep_duration
        end
      end
    rescue ex
      STDERR.puts "Ogg/Opus streaming error: #{ex.message}\n#{ex.backtrace.join("\n")}"
    ensure
      pcm.try &.close
      mux.try &.close # Use try &.close for nilable mux
      # Closing the writer is crucial to signal EOF to the reader.
      pipe_writer.close
    end
  end

  # In the main handler fiber, copy from the pipe to the response.
  # This blocks the handler, but not the server, until the pipe is closed.
  begin
    IO.copy(pipe_reader, env.response)
  ensure
    pipe_reader.close
  end
end

get "/video.mjpg" do |env|
  env.response.content_type = "multipart/x-mixed-replace; boundary=mjpegboundary"
  env.response.headers["Cache-Control"] = "no-cache"
  env.response.headers["Connection"] = "close"
  env.response.headers["Access-Control-Allow-Origin"] = "*"

  manager = GlobalKVM.manager
  unless manager.video_running?
    env.response.status_code = 503
    env.response.print "Stream not available"
    next
  end

  # Directly stream MJPEG frames to the HTTP response using v4cr logic
  begin
    manager.@video_capture.stream_to_http_response(env.response)
  rescue ex
    Log.error { "MJPEG streaming error: #{ex.message}\n#{ex.backtrace.join("\n")}" }
  end
end

post "/api/video/quality" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.manager
  begin
    body = JSON.parse((env.request.body.try &.gets_to_end).to_s)
    quality = body["quality"]?.try(&.as_s)
    if !quality || quality.strip.empty?
      {success: false, message: "No quality specified"}.to_json
    elsif !manager.available_qualities.includes?(quality)
      {success: false, message: "Unsupported quality"}.to_json
    else
      ok = manager.video_quality = quality
      if ok
        {success: true, message: "Video quality set", selected: manager.selected_quality}.to_json
      else
        {success: false, message: "Failed to set video quality"}.to_json
      end
    end
  rescue ex
    {success: false, message: "Invalid request: #{ex.message}"}.to_json
  end
end

post "/api/video/start" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.manager
  success = manager.start_video_stream
  {success: success, message: success ? "Video stream started" : "Failed to start video stream"}.to_json
end

post "/api/video/stop" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.manager
  manager.stop_video_stream
  {success: true, message: "Video stream stopped"}.to_json
end

get "/api/latency-test" do |env|
  env.response.content_type = "application/json"
  env.response.headers["Cache-Control"] = "no-cache"

  manager = GlobalKVM.manager
  unless manager.video_running?
    {success: false, message: "Video not running"}.to_json
    next
  end

  # Return current timestamp for latency measurement
  timestamp = Time.utc.to_unix_ms
  {success: true, timestamp: timestamp, device: manager.video_device}.to_json
end

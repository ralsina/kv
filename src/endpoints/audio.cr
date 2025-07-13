# Audio streaming endpoints
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

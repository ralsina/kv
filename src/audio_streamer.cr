require "./alsa_pcm"
require "opus"
require "./ogg_opus_muxer"

class AudioStreamer
  Log = ::Log.for(self)

  @audio_device : String
  @sample_rate : Int32
  @channels : Int32
  @frame_size : Int32
  @streaming_fiber : Fiber?
  @stop_channel : Channel(Nil)
  @running : Bool

  def initialize(@audio_device : String, @sample_rate : Int32 = 48000, @channels : Int32 = 2, @frame_size : Int32 = 960)
    @stop_channel = Channel(Nil).new
    @running = false
  end

  def start_streaming(output_io : IO)
    return if @running

    @running = true
    @streaming_fiber = spawn do
      mux = nil
      pcm = nil

      begin
        pcm = AlsaPcmCapture.new(@audio_device, @channels, @sample_rate)
        encoder = Opus::Encoder.new(@sample_rate, @frame_size, @channels)
        pcm_buffer = Bytes.new(@frame_size * @channels * 2) # 16-bit samples

        serial = Random.rand(Int32::MAX)
        mux = OggOpusMuxer.new(output_io, serial, @sample_rate, @channels)

        granulepos = 0_i64
        chunk_duration = (@frame_size.to_f / @sample_rate.to_f).seconds

        loop do
          select
          when @stop_channel.receive?
            Log.info { "Audio streaming fiber received stop signal." }
            break
          else
            # Continue streaming
          end

          loop_start_time = Time.monotonic

          frames = pcm.read(pcm_buffer, @frame_size)
          if frames <= 0
            Log.warn { "PCM read failed or stream ended. Stopping audio stream." }
            break
          end

          opus_data = encoder.encode(pcm_buffer)
          if opus_data.empty?
            Log.error { "Opus encoding failed. Stopping audio stream." }
            break
          end

          granulepos += frames
          mux.write_packet(opus_data, granulepos)

          # Pace the loop to send audio in real-time
          elapsed = Time.monotonic - loop_start_time
          sleep_duration = chunk_duration - elapsed
          if sleep_duration > Time::Span.zero
            sleep sleep_duration
          end
        end
      rescue ex
        Log.error(exception: ex) { "Ogg/Opus streaming error: #{ex.message}" }
      ensure
        pcm.try &.close
        mux.try &.close
        output_io.close # Crucial to signal EOF to the reader
        @running = false
        Log.info { "Audio streaming fiber finished." }
      end
    end
  end

  def stop_streaming
    return unless @running
    @stop_channel.send(nil)
    # Wait for the fiber to actually stop
    while @running
      sleep(10.milliseconds)
    end
    @streaming_fiber = nil
  end

  def running? : Bool
    @running
  end
end

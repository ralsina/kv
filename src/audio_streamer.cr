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
  @clients_mutex : Mutex
  @clients : Array(Channel(Tuple(Bytes, Int64)))

  def initialize(@audio_device : String, @sample_rate : Int32 = 48000, @channels : Int32 = 2, @frame_size : Int32 = 960)
    @stop_channel = Channel(Nil).new
    @running = false
    @clients_mutex = Mutex.new
    @clients = [] of Channel(Tuple(Bytes, Int64))
  end

  def add_client(channel : Channel(Tuple(Bytes, Int64)))
    @clients_mutex.synchronize { @clients << channel }
  end

  def remove_client(channel : Channel(Tuple(Bytes, Int64)))
    @clients_mutex.synchronize { @clients.delete(channel) }
    channel.close rescue nil
  end

  # Start the background audio streaming fiber (publisher)
  def start_streaming
    return if @running
    @running = true
    @stop_channel = Channel(Nil).new
    @streaming_fiber = spawn do
      pcm = nil
      encoder = nil
      begin
        Log.info { "[AUDIO] Initializing ALSA PCM capture: device=#{@audio_device}, channels=#{@channels}, rate=#{@sample_rate}" }
        pcm = AlsaPcmCapture.new(@audio_device, @channels, @sample_rate)
        Log.info { "[AUDIO] ALSA PCM capture initialized successfully." }
        encoder = Opus::Encoder.new(@sample_rate, @frame_size, @channels)
        Log.info { "[AUDIO] Opus encoder initialized successfully." }
        pcm_buffer = Bytes.new(@frame_size * @channels * 2)
        granulepos = 0_i64
        chunk_duration = (@frame_size.to_f / @sample_rate.to_f).seconds
        Log.info { "[AUDIO] Entering main audio streaming loop (pub/sub)." }
        loop do
          select
          when @stop_channel.receive?
            Log.info { "[AUDIO] Audio streaming fiber received stop signal." }
            break
          else
            # continue
          end
          loop_start_time = Time.monotonic
          frames = pcm.read(pcm_buffer, @frame_size)
          if frames <= 0
            Log.warn { "[AUDIO] PCM read failed or stream ended. Stopping audio stream." }
            break
          end
          opus_data = encoder.encode(pcm_buffer)
          if opus_data.empty?
            Log.error { "[AUDIO] Opus encoding failed. Stopping audio stream." }
            break
          end
          granulepos += frames
          Log.info { "[AUDIO] Sending opus packet (size: #{opus_data.size}) to #{@clients_mutex.synchronize { @clients.size }} clients" }
          @clients_mutex.synchronize do
            @clients.each do |client|
              begin
                client.send({opus_data.dup, granulepos})
              rescue ex
                Log.warn { "[AUDIO] Failed to send audio packet to client: #{ex.message}" }
              end
            end
          end
          elapsed = Time.monotonic - loop_start_time
          sleep_duration = chunk_duration - elapsed
          if sleep_duration > Time::Span.zero
            # sleep sleep_duration
            Fiber.yield
          end
        end
      rescue ex
        Log.error(exception: ex) { "[AUDIO] Ogg/Opus streaming error: #{ex.message}\nBacktrace: #{ex.backtrace?}" }
      ensure
        Log.info { "[AUDIO] Cleaning up audio resources..." }
        pcm.try &.close
        @running = false
        Log.info { "[AUDIO] Audio streaming fiber finished." }
        # Close all client channels
        @clients_mutex.synchronize do
          @clients.each(&.close)
          @clients.clear
        end
      end
    end
  end

  def stop_streaming
    return unless @running
    @stop_channel.send(nil)
    while @running
      sleep(10.milliseconds)
    end
    @streaming_fiber = nil
  end

  def running? : Bool
    @running
  end

  # For HTTP endpoint: subscribe, stream, and unsubscribe
  def stream_to_http_response(response)
    start_streaming unless running?
    channel = Channel(Tuple(Bytes, Int64)).new(5)
    add_client(channel)
    Log.info { "Audio client connected. Total clients: #{@clients_mutex.synchronize { @clients.size }}" }
    begin
      # Each client gets its own muxer to write headers and packets
      serial = Random.rand(Int32::MAX)
      mux = OggOpusMuxer.new(response, serial, @sample_rate, @channels)
      loop do
        opus_data, granulepos = channel.receive
        mux.write_packet(opus_data, granulepos)
        response.flush
      end
    rescue ex : Channel::ClosedError
      Log.info { "Audio client channel closed." }
    rescue ex
      Log.error(exception: ex) { "Audio client streaming error" }
    ensure
      remove_client(channel)
      Log.info { "Audio client disconnected. Total clients: #{@clients_mutex.synchronize { @clients.size }}" }
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

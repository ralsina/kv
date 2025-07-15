require "./mouse"
require "./kvm_manager"
require "./video_capture"
require "./audio_streamer"

module AntiIdle
  extend self

  @@enabled = false
  @@interval = 60.seconds
  @@jiggle_thread : Fiber? = nil

  def configure(enabled : Bool, interval : Time::Span = 60.seconds)
    @@enabled = enabled
    @@interval = interval
  end

  def start(kvm_manager : KVMManagerV4cr)
    return unless @@enabled
    return if @@jiggle_thread

    @@jiggle_thread = spawn do
      loop do
        sleep @@interval
        jiggle_mouse(kvm_manager) unless client_connected?(kvm_manager)
      end
    end
  end

  def stop
    @@jiggle_thread = nil
  end

  private def client_connected?(kvm_manager)
    video_clients = kvm_manager.video_capture.client_count
    audio_clients = kvm_manager.audio_streamer.client_count
    total_clients = video_clients + audio_clients
    total_clients > 0
  end

  private def jiggle_mouse(kvm_manager)
    return unless kvm_manager.mouse_enabled?
    Log.info { "Jiggling mouse to prevent idle" }
    # Move a small amount and then back
    kvm_manager.send_mouse_move(1, 1)
    ::sleep(0.1.seconds)
    kvm_manager.send_mouse_move(-1, -1)
  end
end

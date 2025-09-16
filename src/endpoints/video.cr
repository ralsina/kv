# Video and audio streaming endpoints
require "../kvm_manager"
require "../alsa_pcm"
require "opus"
require "../ogg_opus_muxer"

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
    elsif !quality.starts_with?("jpeg:") && !quality.starts_with?("fps:") && !manager.available_qualities.includes?(quality)
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

post "/api/video/redetect-device" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.manager

  old_device = manager.video_device
  Log.info { "Manual video device re-detection requested. Current device: #{old_device}" }

  # Check if current device is still available
  if manager.video_device_available?
    # Current device is available, but user may want to force re-detection anyway
    # This could be useful if the device is having issues but still exists
    begin
      body = JSON.parse((env.request.body.try &.gets_to_end).to_s || "{}")
      force = body["force"]?.try(&.as_bool) || false

      if force
        Log.info { "Forcing video device re-detection even though current device exists" }
        success = manager.handle_video_device_failure
        new_device = manager.video_device

        if success && new_device != old_device
          {
            success:    true,
            message:    "Successfully switched to different video device",
            old_device: old_device,
            new_device: new_device,
          }.to_json
        elsif success
          {
            success: true,
            message: "Re-detection completed, same device selected",
            device:  old_device,
          }.to_json
        else
          {
            success: false,
            message: "Failed to find alternative video device",
            device:  old_device,
          }.to_json
        end
      else
        {
          success:   true,
          message:   "Current video device is available",
          device:    old_device,
          available: true,
        }.to_json
      end
    rescue ex
      {
        success:   true,
        message:   "Current video device is available",
        device:    old_device,
        available: true,
      }.to_json
    end
  else
    Log.warn { "Current video device #{old_device} is not available, attempting re-detection..." }
    success = manager.handle_video_device_failure
    new_device = manager.video_device

    if success
      {
        success:    true,
        message:    "Successfully switched video device",
        old_device: old_device,
        new_device: new_device,
      }.to_json
    else
      {
        success:    false,
        message:    "Failed to find alternative video device",
        old_device: old_device,
      }.to_json
    end
  end
end

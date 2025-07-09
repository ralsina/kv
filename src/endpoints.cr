require "kemal"
require "json"
require "ecr"
require "./kvm_manager"

# Global KVM manager module
module GlobalKVM
  Log = ::Log.for(self)

  @@manager : KVMManagerV4cr?

  def self.set_manager(manager : KVMManagerV4cr)
    @@manager = manager
  end

  def self.get_manager
    if manager = @@manager
      manager
    else
      raise "KVM manager not initialized"
    end
  end
end

# Robust, centrally managed MJPEG stream
get "/video.mjpg" do |env|
  env.response.content_type = "multipart/x-mixed-replace; boundary=mjpegboundary"
  env.response.headers["Cache-Control"] = "no-cache"
  env.response.headers["Connection"] = "close"
  env.response.headers["Access-Control-Allow-Origin"] = "*"

  manager = GlobalKVM.get_manager
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

# Main KVM interface
get "/" do
  render "templates/app.ecr"
end

# API endpoints for video control
post "/api/video/start" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.get_manager
  success = manager.start_video_stream
  {success: success, message: success ? "Video stream started" : "Failed to start video stream"}.to_json
end

post "/api/video/stop" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.get_manager
  manager.stop_video_stream
  {success: true, message: "Video stream stopped"}.to_json
end

# API endpoints for keyboard control
post "/api/keyboard/keys" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.get_manager

  begin
    if env.request.body
      body = JSON.parse((env.request.body.try &.gets_to_end).to_s)
    else
      next
    end

    # Fix JSON array parsing
    keys = [] of String
    if keys_json = body["keys"]?
      if keys_json.as_a?
        keys = keys_json.as_a.map(&.as_s)
      end
    end

    modifiers = [] of String
    if modifiers_json = body["modifiers"]?
      if modifiers_json.as_a?
        modifiers = modifiers_json.as_a.map(&.as_s)
      end
    end

    if keys.empty?
      {success: false, message: "No keys specified"}.to_json
    else
      result = manager.send_keys(keys, modifiers)
      result.to_json
    end
  rescue ex
    {success: false, message: "Invalid request: #{ex.message}"}.to_json
  end
end

post "/api/keyboard/combination" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.get_manager

  begin
    body = JSON.parse((env.request.body.try &.gets_to_end).to_s)

    # Fix JSON array parsing
    keys = [] of String
    if keys_json = body["keys"]?
      if keys_json.as_a?
        keys = keys_json.as_a.map(&.as_s)
      end
    end

    modifiers = [] of String
    if modifiers_json = body["modifiers"]?
      if modifiers_json.as_a?
        modifiers = modifiers_json.as_a.map(&.as_s)
      end
    end

    if keys.empty?
      {success: false, message: "No keys specified"}.to_json
    else
      result = manager.send_keys(keys, modifiers)
      result.to_json
    end
  rescue ex
    {success: false, message: "Invalid request: #{ex.message}"}.to_json
  end
end

post "/api/keyboard/text" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.get_manager

  begin
    body = JSON.parse((env.request.body.try &.gets_to_end).to_s)
    text = body["text"]?.try(&.as_s)

    if !text || text.strip.empty?
      {success: false, message: "No text specified"}.to_json
    else
      result = manager.send_text(text)
      result.to_json
    end
  rescue ex
    {success: false, message: "Invalid request: #{ex.message}"}.to_json
  end
end

# Relative mouse movement
post "/api/mouse/move" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.get_manager

  begin
    body = JSON.parse((env.request.body.try &.gets_to_end).to_s)
    x_delta = body["x"]?.try(&.as_i) || 0
    y_delta = body["y"]?.try(&.as_i) || 0

    # Parse button state if provided (for drag support)
    buttons = [] of String
    if buttons_json = body["buttons"]?
      if buttons_json.as_a?
        buttons = buttons_json.as_a.map(&.as_s)
      end
    end

    Log.debug { "Received relative mouse movement: dx=#{x_delta}, dy=#{y_delta}, buttons=#{buttons}" }

    # Use the move method that preserves button state
    if buttons.empty?
      result = manager.send_mouse_move(x_delta, y_delta)
    else
      result = manager.send_mouse_move_with_buttons(x_delta, y_delta, buttons)
    end

    result.to_json
  rescue ex
    {success: false, message: "Invalid request: #{ex.message}"}.to_json
  end
end

# Mouse wheel
post "/api/mouse/wheel" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.get_manager

  begin
    body = JSON.parse((env.request.body.try &.gets_to_end).to_s)
    wheel_delta = body["delta"]?.try(&.as_i) || 0

    Log.debug { "Received mouse wheel: delta=#{wheel_delta}" }
    result = manager.send_mouse_wheel(wheel_delta)
    result.to_json
  rescue ex
    {success: false, message: "Invalid request: #{ex.message}"}.to_json
  end
end

# Mouse click (without movement)
post "/api/mouse/click" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.get_manager

  begin
    body = JSON.parse((env.request.body.try &.gets_to_end).to_s)
    button = body["button"]?.try(&.as_s)

    if !button || button.strip.empty?
      {success: false, message: "No button specified"}.to_json
    else
      Log.debug { "Received mouse click: button=#{button}" }
      result = manager.send_mouse_click(button)
      result.to_json
    end
  rescue ex
    {success: false, message: "Invalid request: #{ex.message}"}.to_json
  end
end

# Mouse press (button down)
post "/api/mouse/press" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.get_manager

  begin
    body = JSON.parse((env.request.body.try &.gets_to_end).to_s)
    button = body["button"]?.try(&.as_s)

    if !button || button.strip.empty?
      {success: false, message: "No button specified"}.to_json
    else
      Log.debug { "Received mouse press: button=#{button}" }
      result = manager.send_mouse_press(button)
      result.to_json
    end
  rescue ex
    {success: false, message: "Invalid request: #{ex.message}"}.to_json
  end
end

# Mouse release (button up)
post "/api/mouse/release" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.get_manager

  begin
    body = JSON.parse((env.request.body.try &.gets_to_end).to_s)
    button = body["button"]?.try(&.as_s)

    if !button || button.strip.empty?
      {success: false, message: "No button specified"}.to_json
    else
      Log.debug { "Received mouse release: button=#{button}" }
      result = manager.send_mouse_release(button)
      result.to_json
    end
  rescue ex
    {success: false, message: "Invalid request: #{ex.message}"}.to_json
  end
end

get "/api/status" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.get_manager
  manager.status.to_json
end

get "/api/time" do |env|
  env.response.content_type = "application/json"
  {timestamp: Time.utc.to_unix_ms}.to_json
end

get "/api/latency-test" do |env|
  env.response.content_type = "application/json"
  env.response.headers["Cache-Control"] = "no-cache"

  manager = GlobalKVM.get_manager
  unless manager.video_running?
    {success: false, message: "Video not running"}.to_json
    next
  end

  # Return current timestamp for latency measurement
  timestamp = Time.utc.to_unix_ms
  {success: true, timestamp: timestamp, device: manager.video_device}.to_json
end

# Health check
get "/health" do
  "OK"
end

# WebSocket endpoint for high-performance input events
ws "/ws/input" do |socket|
  manager = GlobalKVM.get_manager

  Log.debug { "WebSocket client connected" }

  # Send initial status
  status = manager.status
  socket.send({
    type: "status",
    data: status,
  }.to_json)

  socket.on_message do |message|
    begin
      data = JSON.parse(message)
      event_type = data["type"]?.try(&.as_s)

      case event_type
      when "mouse_move"
        x_delta = data["x"]?.try(&.as_i) || 0
        y_delta = data["y"]?.try(&.as_i) || 0

        # Parse button state if provided (for drag support)
        buttons = [] of String
        if buttons_json = data["buttons"]?
          if buttons_json.as_a?
            buttons = buttons_json.as_a.map(&.as_s)
          end
        end

        # Use the appropriate move method based on button state
        if buttons.empty?
          result = manager.send_mouse_move(x_delta, y_delta)
        else
          result = manager.send_mouse_move_with_buttons(x_delta, y_delta, buttons)
        end

        # Only send response for errors to minimize traffic
        unless result[:success]
          socket.send({
            type:    "error",
            message: result[:message],
          }.to_json)
        end
      when "mouse_click"
        button = data["button"]?.try(&.as_s)
        if button
          result = manager.send_mouse_click(button)

          # Send click confirmation
          socket.send({
            type:    "mouse_click_result",
            success: result[:success],
            button:  button,
          }.to_json)
        end
      when "mouse_press"
        button = data["button"]?.try(&.as_s)
        if button
          result = manager.send_mouse_press(button)

          # Only send response for errors
          unless result[:success]
            socket.send({
              type:    "error",
              message: result[:message],
            }.to_json)
          end
        end
      when "mouse_release"
        button = data["button"]?.try(&.as_s)
        if button
          result = manager.send_mouse_release(button)

          # Only send response for errors
          unless result[:success]
            socket.send({
              type:    "error",
              message: result[:message],
            }.to_json)
          end
        end
      when "mouse_wheel"
        wheel_delta = data["delta"]?.try(&.as_i) || 0
        if wheel_delta != 0
          result = manager.send_mouse_wheel(wheel_delta)

          # Only send response for errors
          unless result[:success]
            socket.send({
              type:    "error",
              message: result[:message],
            }.to_json)
          end
        end
      when "key_press"
        key = data["key"]?.try(&.as_s)
        if key
          # Send single key as an array
          result = manager.send_keys([key])

          # Only send response for errors
          unless result[:success]
            socket.send({
              type:    "error",
              message: result[:message],
            }.to_json)
          end
        end
      when "key_combination"
        modifiers = data["modifiers"]?.try(&.as_a.map(&.as_s)) || [] of String
        keys = data["keys"]?.try(&.as_a.map(&.as_s)) || [] of String

        if keys.size > 0
          result = manager.send_keys(keys, modifiers)

          # Only send response for errors
          unless result[:success]
            socket.send({
              type:    "error",
              message: result[:message],
            }.to_json)
          end
        end
      when "ping"
        # Respond to ping for connection health check
        socket.send({type: "pong"}.to_json)
      else
        socket.send({
          type:    "error",
          message: "Unknown event type: #{event_type}",
        }.to_json)
      end
    rescue ex
      Log.error { "WebSocket message parse error: #{ex.message}" }
      socket.send({
        type:    "error",
        message: "Invalid message format",
      }.to_json)
    end
  end

  socket.on_close do
    Log.debug { "WebSocket client disconnected" }
  end
end

# Mass storage API (new model)
get "/api/storage/images" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.get_manager
  images = manager.@mass_storage.available_images
  {success: true, images: images, selected: manager.@mass_storage.selected_image}.to_json
end

post "/api/storage/select" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.get_manager
  begin
    body = JSON.parse((env.request.body.try &.gets_to_end).to_s)
    image = body["image"]?.try(&.as_s)
    # Allow null/empty to detach
    image = nil if image && image.strip.empty?
    result = manager.@mass_storage.select_image(image)
    # Re-setup HID devices to apply new image
    manager.setup_hid_devices
    result.to_json
  rescue ex
    {success: false, message: "Invalid request: #{ex.message}"}.to_json
  end
end

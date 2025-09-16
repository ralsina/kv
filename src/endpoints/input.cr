# Keyboard and mouse input endpoints, WebSocket input
require "../kvm_manager"

##
# WebSocket endpoint for real-time keyboard and mouse input
#
# Data format (JSON):
# {
#   type: "mouse_move", x: Int, y: Int, buttons?: [String]
# }
# {
#   type: "mouse_click", button: String
# }
# {
#   type: "mouse_press", button: String
# }
# {
#   type: "mouse_release", button: String
# }
# {
#   type: "mouse_wheel", delta: Int
# }
# {
#   type: "key_press", key: String
# }
# {
#   type: "key_combination", keys: [String], modifiers?: [String]
# }
# {
#   type: "ping"
# }
#
# The server responds with status, error, or mouse_click_result messages as appropriate.
ws "/ws/input" do |socket|
  manager = GlobalKVM.manager

  Log.debug { "WebSocket client connected" }

  # Send initial status
  status = manager.status
  socket.send({
    type: "status",
    data: status,
  }.to_json)

  # Helper to send error if needed
  send_error = ->(msg : String) do
    socket.send({type: "error", message: msg}.to_json)
  end

  # Helper to run an action and send error if needed
  handle_result = ->(result : Hash(Symbol, String | Bool) | NamedTuple(success: Bool, message: String)) do
    unless result[:success]
      socket.send({type: "error", message: result[:message]}.to_json)
    end
  end

  socket.on_message do |message|
    Log.info { "Received WebSocket message: #{message}" }
    begin
      data = JSON.parse(message)
      event_type = data["type"]?.try(&.as_s)

      case event_type
      when "mouse_move"
        x_delta = data["x"]?.try(&.as_i) || 0
        y_delta = data["y"]?.try(&.as_i) || 0
        buttons_json = data["buttons"]?
        buttons = buttons_json && buttons_json.as_a? ? buttons_json.as_a.map(&.as_s) : [] of String
        result = buttons.empty? ? manager.send_mouse_move(x_delta, y_delta) : manager.send_mouse_move_with_buttons(x_delta, y_delta, buttons)
        handle_result.call(result)
      when "mouse_click"
        button = data["button"]?.try(&.as_s)
        if button
          result = manager.send_mouse_click(button)
          socket.send({type: "mouse_click_result", success: result[:success], button: button}.to_json)
        end
      when "mouse_press"
        button = data["button"]?.try(&.as_s)
        if button
          result = manager.send_mouse_press(button)
          handle_result.call(result)
        end
      when "mouse_release"
        button = data["button"]?.try(&.as_s)
        if button
          result = manager.send_mouse_release(button)
          handle_result.call(result)
        end
      when "mouse_wheel"
        wheel_delta = data["delta"]?.try(&.as_i) || 0
        if wheel_delta != 0
          result = manager.send_mouse_wheel(wheel_delta)
          handle_result.call(result)
        end
      when "key_press"
        key = data["key"]?.try(&.as_s)
        if key
          result = manager.send_keys([key])
          handle_result.call(result)
        end
      when "key_combination"
        modifiers = data["modifiers"]?.try(&.as_a.map(&.as_s)) || [] of String
        keys = data["keys"]?.try(&.as_a.map(&.as_s)) || [] of String
        if keys.size > 0
          result = manager.send_keys(keys, modifiers)
          handle_result.call(result)
        end
      when "text"
        text = data["text"]?.try(&.as_s)
        if text && !text.empty?
          result = manager.send_text(text)
          handle_result.call(result)
        else
          Log.warn { "No text provided in WebSocket text event" }
          send_error.call("No text provided")
        end
      when "ping"
        socket.send({type: "pong"}.to_json)
      when "mouse_absolute"
        x = data["x"]?.try(&.as_i) || 0
        y = data["y"]?.try(&.as_i) || 0
        buttons_json = data["buttons"]?
        buttons = buttons_json && buttons_json.as_a? ? buttons_json.as_a.map(&.as_s) : [] of String
        result = manager.send_mouse_absolute_move(x, y, buttons)
        handle_result.call(result)
      else
        send_error.call("Unknown event type: #{event_type}")
      end
    rescue ex
      Log.error { "WebSocket message parse error: #{ex.message}" }
      send_error.call("Invalid message format")
    end
  end

  socket.on_close do
    Log.debug { "WebSocket client disconnected" }

    # Release any stuck keys when client disconnects
    begin
      result = manager.release_all_keys
      Log.info { "Cleanup on disconnect: #{result[:message]}" }
    rescue ex
      Log.error { "Failed to cleanup stuck keys on disconnect: #{ex.message}" }
    end
  end
end

require "log"
require "json"

# WebSocket connection manager for broadcasting messages to all connected clients
class WebSocketManager
  Log = ::Log.for("websocket_manager")

  @@instance : WebSocketManager?
  @sockets : Array(HTTP::WebSocket)
  @mutex : Mutex

  def self.instance
    @@instance ||= new
  end

  def initialize
    @sockets = [] of HTTP::WebSocket
    @mutex = Mutex.new
  end

  # Register a new WebSocket connection
  def register_socket(socket : HTTP::WebSocket)
    @mutex.synchronize do
      @sockets << socket
    end
    Log.debug { "WebSocket registered. Total connections: #{@sockets.size}" }
  end

  # Unregister a WebSocket connection
  def unregister_socket(socket : HTTP::WebSocket)
    @mutex.synchronize do
      @sockets.delete(socket)
    end
    Log.debug { "WebSocket unregistered. Total connections: #{@sockets.size}" }
  end

  # Broadcast a message to all connected clients
  def broadcast(message : String)
    @mutex.synchronize do
      @sockets.each do |socket|
        begin
          socket.send(message)
        rescue ex
          Log.warn { "Failed to send message to WebSocket client: #{ex.message}" }
          # Remove dead socket
          @sockets.delete(socket)
        end
      end
    end
  end

  # Broadcast a JSON message to all connected clients
  def broadcast_json(data : Hash(String, JSON::Any::Type))
    broadcast(data.to_json)
  end

  # Get the number of connected clients
  def client_count : Int32
    @mutex.synchronize { @sockets.size }
  end

  # Send device status update to all clients
  def send_device_status(available : Bool, device : String, message : String? = nil)
    data = {
      "type"  => "device_status",
      "video" => {
        "available" => available,
        "device"    => device,
        "message"   => message || (available ? "Video device connected" : "Video device disconnected"),
      },
    }
    broadcast(data.to_json)
  end

  # Send warning message to all clients
  def send_warning(message : String)
    data = {
      "type"    => "warning",
      "message" => message,
    }
    broadcast_json(data)
  end

  # Send info message to all clients
  def send_info(message : String)
    data = {
      "type"    => "info",
      "message" => message,
    }
    broadcast_json(data)
  end
end

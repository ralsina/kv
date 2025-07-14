# Status, time, and health endpoints
require "../kvm_manager"

get "/api/status" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.manager
  status = manager.status
  Log.debug { "/api/status called" }
  status.to_json
end

get "/api/time" do |env|
  env.response.content_type = "application/json"
  {timestamp: Time.utc.to_unix_ms}.to_json
end

get "/health" do
  "OK"
end

# Ethernet/ECM endpoints
require "../kvm_manager"

post "/api/ethernet/enable" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.manager
  result = manager.enable_ecm
  result.to_json
end

post "/api/ethernet/disable" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.manager
  result = manager.disable_ecm
  result.to_json
end

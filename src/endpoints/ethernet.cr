# Ethernet/ECM endpoints
require "../kvm_manager"

post "/api/ethernet/enable" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.manager

  if manager.ethernet_disabled?
    env.response.status_code = 403
    next({success: false, message: "Ethernet is disabled"}.to_json)
  end

  result = manager.enable_ecm
  result.to_json
end

post "/api/ethernet/disable" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.manager

  if manager.ethernet_disabled?
    env.response.status_code = 403
    next({success: false, message: "Ethernet is disabled"}.to_json)
  end

  result = manager.disable_ecm
  result.to_json
end

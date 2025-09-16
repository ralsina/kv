# Main KVM interface and endpoint includes
get "/" do
  render "templates/app.ecr"
end

get "/mobile" do
  render "templates/mobile.ecr"
end

# Emergency endpoint to release all stuck keys
post "/api/release-keys" do
  manager = GlobalKVM.manager
  result = manager.release_all_keys
  {success: result[:success], message: result[:message]}.to_json
end

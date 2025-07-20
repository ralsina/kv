# Main KVM interface and endpoint includes
get "/" do
  render "templates/app.ecr"
end

get "/mobile" do
  render "templates/mobile.ecr"
end

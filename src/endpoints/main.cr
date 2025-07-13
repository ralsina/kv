# Main KVM interface and endpoint includes

require "./video.cr"
require "./input.cr"
require "./storage.cr"
require "./ethernet.cr"
require "./status.cr"

get "/" do
  render "templates/app.ecr"
end

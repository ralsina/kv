# KVM input switch endpoint
require "../kvm_manager"

post "/api/switch" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.manager

  begin
    body = JSON.parse((env.request.body.try &.gets_to_end).to_s)
    slot = body["slot"]?.try(&.as_i)

    count = manager.ch9329_input_count
    unless slot && (1..count).includes?(slot)
      {success: false, message: "Slot must be between 1 and #{count}"}.to_json
      next
    end

    # Sends the --ch9329-kvm-input-key-sequence pattern (e.g. ctrl+ctrl+#)
    # with "#" replaced by the slot number, via the active HID backend.
    result = manager.switch_kvm_input(slot)
    if result[:success]
      {success: true, message: result[:message]}.to_json
    else
      {success: false, message: result[:message]}.to_json
    end
  rescue ex
    {success: false, message: "Invalid request: #{ex.message}"}.to_json
  end
end

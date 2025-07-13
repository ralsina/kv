# Audio streaming endpoints
require "../kvm_manager"
require "../alsa_pcm"
require "opus"
require "../ogg_opus_muxer"

get "/audio.ogg" do |env|
  env.response.content_type = "audio/ogg"
  env.response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
  env.response.headers["Pragma"] = "no-cache"
  env.response.headers["Expires"] = "0"
  env.response.headers["Connection"] = "keep-alive"
  env.response.headers["Access-Control-Allow-Origin"] = "*"

  manager = GlobalKVM.manager
  unless manager.audio_running?
    manager.start_audio_stream(env.response)
  end
end

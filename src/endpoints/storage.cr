# Mass storage (USB image) endpoints
require "../kvm_manager"
require "mime/multipart"

get "/api/storage/images" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.manager

  if manager.mass_storage_disabled?
    env.response.status_code = 403
    next({success: false, message: "Mass storage is disabled"}.to_json)
  end

  if mass_storage = manager.mass_storage_manager
    images = mass_storage.available_images.map do |img|
      File.basename(img)
    end
    selected = mass_storage.selected_image
    selected = File.basename(selected) if selected
    {success: true, images: images, selected: selected}.to_json
  else
    env.response.status_code = 500
    {success: false, message: "Mass storage manager not available"}.to_json
  end
end

post "/api/storage/select" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.manager

  if manager.mass_storage_disabled?
    env.response.status_code = 403
    next({success: false, message: "Mass storage is disabled"}.to_json)
  end

  begin
    body = JSON.parse((env.request.body.try &.gets_to_end).to_s)
    image = body["image"]?
    # Allow null/empty to detach
    if !image || image.to_s.strip.empty?
      image = nil
    else
      image = image.to_s
    end
    # Use KVMManager to ensure decompression and get the image to mount
    decompress_result = manager.ensure_decompressed_image(image)
    unless decompress_result[:success]
      next({success: false, message: decompress_result[:message]}.to_json)
    end
    selected_img = decompress_result[:raw_image]
    if mass_storage = manager.mass_storage_manager
      result = mass_storage.select_image(selected_img)
    else
      next({success: false, message: "Mass storage manager not available"}.to_json)
    end
    # Re-setup HID devices to apply new image
    manager.setup_hid_devices
    result.to_json
  rescue ex
    {success: false, message: "Invalid request: #{ex.message}"}.to_json
  end
end

post "/api/storage/upload" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.manager

  if manager.mass_storage_disabled?
    env.response.status_code = 403
    next({success: false, message: "Mass storage is disabled"}.to_json)
  end

  begin
    # Get the uploaded file from the form field named "file"
    upload = env.params.files["file"]?
    unless upload && upload.tempfile
      env.response.status_code = 400
      next({success: false, message: "No file uploaded"}.to_json)
    end

    orig_filename = upload.filename.to_s
    temp_file = File.tempfile("upload") { |file_handle| IO.copy(upload.tempfile, file_handle) }

    manager = GlobalKVM.manager
    result = manager.upload_and_decompress_image(temp_file.path, orig_filename)
    temp_file.delete
    if result[:success]
      {success: true, message: result[:message], filename: result[:filename]}.to_json
    else
      env.response.status_code = 500
      {success: false, message: result[:message]}.to_json
    end
  rescue ex
    env.response.status_code = 500
    {success: false, message: "Upload failed: #{ex.message}"}.to_json
  end
end

delete "/api/storage/images/:filename" do |env|
  env.response.content_type = "application/json"
  manager = GlobalKVM.manager

  if manager.mass_storage_disabled?
    env.response.status_code = 403
    next({success: false, message: "Mass storage is disabled"}.to_json)
  end

  filename = env.params.url["filename"]
  if filename.nil? || filename.strip.empty?
    env.response.status_code = 400
    next({success: false, message: "Filename not provided"}.to_json)
  end

  if mass_storage = manager.mass_storage_manager
    result = mass_storage.delete_image(filename)
  else
    env.response.status_code = 500
    next({success: false, message: "Mass storage manager not available"}.to_json)
  end
  if result[:success]
    {success: true, message: result[:message]}.to_json
  else
    env.response.status_code = 500
    {success: false, message: result[:message]}.to_json
  end
end

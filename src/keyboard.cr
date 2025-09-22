require "file_utils"
require "./keyboard_layouts"

# HID Keyboard Module for USB Gadget functionality
module HIDKeyboard
  Log = ::Log.for(self)

  # Current keyboard layout
  @@layout : KeyboardLayouts::Layout = KeyboardLayouts::QWERTY

  # Get current layout
  def self.layout
    @@layout
  end

  # Set keyboard layout
  def self.layout=(layout_name : String)
    @@layout = KeyboardLayouts.get_layout(layout_name)
    Log.info { "Keyboard layout set to: #{@@layout.name}" }
  end

  # Helper method for writing to HID device with retry mechanism
  private def self.write_with_retry(fd : Int32, data : Bytes, operation_name : String) : Bool
    max_retries = 5
    retry_delay = 0.001.seconds # Start with 1ms

    max_retries.times do |attempt|
      bytes_written = LibC.write(fd, data, data.size)

      if bytes_written == data.size
        return true # Success
      elsif bytes_written < 0
        errno_val = Errno.value
        if errno_val == Errno::EAGAIN || errno_val == Errno::EWOULDBLOCK
          if attempt < max_retries - 1
            Log.debug { "#{operation_name} would block, retry #{attempt + 1}/#{max_retries} in #{retry_delay.total_milliseconds}ms" }
            sleep retry_delay
            retry_delay *= 2 # Exponential backoff
            next
          else
            Log.warn { "#{operation_name} would block after #{max_retries} retries - host may not be reading HID reports" }
          end
        else
          Log.error { "#{operation_name} failed with errno: #{errno_val}" }
        end
      else
        Log.error { "#{operation_name} incomplete: #{bytes_written}/#{data.size} bytes" }
      end

      return false # Failure
    end

    false
  end

  def self.create_keyboard_report(keys : Array(String), modifiers : Array(String) = [] of String) : Bytes
    report = Bytes.new(8, 0_u8)
    key_index = 0

    # Apply modifiers first
    modifiers.each do |mod|
      if mod_val = @@layout.modifiers[mod.downcase]?
        report[0] |= mod_val
      end
    end

    # Apply keys (max 6 simultaneous keys)
    keys.each do |key|
      break if key_index >= 6

      # First check special keys
      if hid_code = @@layout.special_keys[key.downcase]?
        report[2 + key_index] = hid_code
        key_index += 1
      elsif key.size == 1
        # Handle single character
        char = key[0]
        # Convert uppercase to lowercase and add shift
        if char >= 'A' && char <= 'Z'
          char = char.downcase
          report[0] |= @@layout.modifiers["shift"]
        end

        if hid_code = @@layout.char_to_hid[char]?
          # Check if this key requires shift modifier
          if @@layout.shift_chars.includes?(char)
            report[0] |= @@layout.modifiers["shift"]
          end
          report[2 + key_index] = hid_code
          key_index += 1
        end
      end
    end

    report
  end

  def self.send_keyboard_report(device_path : String, report : Bytes)
    # Open with O_RDWR and O_NONBLOCK to prevent hanging when host isn't reading
    fd = LibC.open(device_path, LibC::O_RDWR | LibC::O_NONBLOCK, 0o666)
    if fd < 0
      raise "Failed to open HID device #{device_path}"
    end

    begin
      # Send the key report (key press)
      Log.debug { "Writing key press: #{report.map { |byte| "%02x" % byte }.join(" ")}" }
      press_success = write_with_retry(fd, report, "Key press")

      # Minimal delay to separate key press and release
      sleep 0.001.seconds

      # Always attempt to send key release, even if press failed
      # This prevents keys from getting stuck
      empty_report = Bytes.new(8, 0_u8)
      Log.debug { "Writing key release: #{empty_report.map { |byte| "%02x" % byte }.join(" ")}" }
      release_success = write_with_retry(fd, empty_report, "Key release")

      Log.debug { "HID write completed - press: #{press_success}, release: #{release_success}" }
    ensure
      LibC.close(fd)
    end
  end

  def self.send_text(device_path : String, text : String)
    text.each_char do |char|
      # Clear report first (like C code)
      report = Bytes.new(8, 0_u8)

      # Handle character using layout mapping
      if char == ' '
        # Handle space explicitly
        report[2] = @@layout.special_keys["space"]
      elsif hid_code = @@layout.char_to_hid[char]?
        # Use layout mapping for characters
        if @@layout.shift_chars.includes?(char)
          report[0] = @@layout.modifiers["shift"]
        end
        report[2] = hid_code
      else
        # Skip unsupported characters
        Log.debug { "Skipping unsupported character: '#{char}' (#{char.ord})" }
        next
      end

      # Use non-blocking writes to prevent hanging
      fd = LibC.open(device_path, LibC::O_RDWR | LibC::O_NONBLOCK, 0o666)
      if fd < 0
        Log.error { "Failed to open HID device for char '#{char}'" }
        next
      end

      begin
        # Send key press
        Log.debug { "Text char '#{char}' press: #{report.map { |byte| "%02x" % byte }.join(" ")}" }
        press_success = write_with_retry(fd, report, "Text char '#{char}' press")

        sleep 0.001.seconds

        # Send key release (clear report like C code)
        empty_report = Bytes.new(8, 0_u8)
        Log.debug { "Text char '#{char}' release: #{empty_report.map { |byte| "%02x" % byte }.join(" ")}" }
        release_success = write_with_retry(fd, empty_report, "Text char '#{char}' release")

        # Only continue to next character if both press and release succeeded
        break unless press_success && release_success

        sleep 0.001.seconds # Minimal delay between characters for ultra-fast typing
      ensure
        LibC.close(fd)
      end
    end
  end
end

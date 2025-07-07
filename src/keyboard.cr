require "file_utils"

# HID Keyboard Module for USB Gadget functionality
module HIDKeyboard
  Log = ::Log.for(self)

  # Key modifier mappings
  KMOD = {
    "ctrl"        => 0x01_u8,
    "left-ctrl"   => 0x01_u8,
    "right-ctrl"  => 0x10_u8,
    "shift"       => 0x02_u8,
    "left-shift"  => 0x02_u8,
    "right-shift" => 0x20_u8,
    "alt"         => 0x04_u8,
    "left-alt"    => 0x04_u8,
    "right-alt"   => 0x40_u8,
    "meta"        => 0x08_u8,
    "left-meta"   => 0x08_u8,
    "right-meta"  => 0x80_u8,
  }

  # Special key value mappings
  KVAL = {
    # Letters are handled dynamically in char_to_usage
    # Numbers and symbols
    "1" => 0x1e_u8,
    "2" => 0x1f_u8,
    "3" => 0x20_u8,
    "4" => 0x21_u8,
    "5" => 0x22_u8,
    "6" => 0x23_u8,
    "7" => 0x24_u8,
    "8" => 0x25_u8,
    "9" => 0x26_u8,
    "0" => 0x27_u8,
    # Special characters and punctuation
    "-"  => 0x2d_u8, # Minus/hyphen
    "="  => 0x2e_u8, # Equal
    "["  => 0x2f_u8, # Left bracket
    "]"  => 0x30_u8, # Right bracket
    "\\" => 0x31_u8, # Backslash
    ";"  => 0x33_u8, # Semicolon
    "'"  => 0x34_u8, # Apostrophe/quote
    "`"  => 0x35_u8, # Grave accent/backtick
    ","  => 0x36_u8, # Comma
    "."  => 0x37_u8, # Period
    "/"  => 0x38_u8, # Forward slash
    # Shifted symbols (using shift modifier)
    "!"  => 0x1e_u8, # Shift + 1
    "@"  => 0x1f_u8, # Shift + 2
    "#"  => 0x20_u8, # Shift + 3
    "$"  => 0x21_u8, # Shift + 4
    "%"  => 0x22_u8, # Shift + 5
    "^"  => 0x23_u8, # Shift + 6
    "&"  => 0x24_u8, # Shift + 7
    "*"  => 0x25_u8, # Shift + 8
    "("  => 0x26_u8, # Shift + 9
    ")"  => 0x27_u8, # Shift + 0
    "_"  => 0x2d_u8, # Shift + -
    "+"  => 0x2e_u8, # Shift + =
    "{"  => 0x2f_u8, # Shift + [
    "}"  => 0x30_u8, # Shift + ]
    "|"  => 0x31_u8, # Shift + \
    ":"  => 0x33_u8, # Shift + ;
    "\"" => 0x34_u8, # Shift + '
    "~"  => 0x35_u8, # Shift + `
    "<"  => 0x36_u8, # Shift + ,
    ">"  => 0x37_u8, # Shift + .
    "?"  => 0x38_u8, # Shift + /
    # Control keys
    "enter"     => 0x28_u8,
    "return"    => 0x28_u8,
    "esc"       => 0x29_u8,
    "escape"    => 0x29_u8,
    "backspace" => 0x2a_u8,
    "tab"       => 0x2b_u8,
    "space"     => 0x2c_u8,
    "spacebar"  => 0x2c_u8,
    "caps-lock" => 0x39_u8,
    # Function keys
    "f1"       => 0x3a_u8,
    "f2"       => 0x3b_u8,
    "f3"       => 0x3c_u8,
    "f4"       => 0x3d_u8,
    "f5"       => 0x3e_u8,
    "f6"       => 0x3f_u8,
    "f7"       => 0x40_u8,
    "f8"       => 0x41_u8,
    "f9"       => 0x42_u8,
    "f10"      => 0x43_u8,
    "f11"      => 0x44_u8,
    "f12"      => 0x45_u8,
    "insert"   => 0x49_u8,
    "home"     => 0x4a_u8,
    "pageup"   => 0x4b_u8,
    "delete"   => 0x4c_u8,
    "del"      => 0x4c_u8,
    "end"      => 0x4d_u8,
    "pagedown" => 0x4e_u8,
    "right"    => 0x4f_u8,
    "left"     => 0x50_u8,
    "down"     => 0x51_u8,
    "up"       => 0x52_u8,
    "num-lock" => 0x53_u8,
    "kp-enter" => 0x58_u8,
  }

  def self.create_keyboard_report(keys : Array(String), modifiers : Array(String) = [] of String) : Bytes
    report = Bytes.new(8, 0_u8)
    key_index = 0

    # Apply modifiers first
    modifiers.each do |mod|
      if mod_val = KMOD[mod.downcase]?
        report[0] |= mod_val
      end
    end

    # Apply keys (max 6 simultaneous keys)
    keys.each do |key|
      break if key_index >= 6

      # First check special keys in KVAL
      if val = KVAL[key]?
        # Check if this key requires shift modifier
        shifted_chars = ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+", "{", "}", "|", ":", "\"", "~", "<", ">", "?"]
        if shifted_chars.includes?(key)
          report[0] |= KMOD["shift"]
        end
        report[2 + key_index] = val
        key_index += 1
      elsif key.size == 1
        # Handle single character
        char = key[0]
        if char >= 'a' && char <= 'z'
          # Lowercase letters
          report[2 + key_index] = (char.ord - 'a'.ord + 0x04).to_u8
          key_index += 1
        elsif char >= 'A' && char <= 'Z'
          # Uppercase letters - add shift modifier and use lowercase equivalent
          report[0] |= KMOD["shift"]
          report[2 + key_index] = (char.downcase.ord - 'a'.ord + 0x04).to_u8
          key_index += 1
        elsif char >= '0' && char <= '9'
          # Numbers
          if val = KVAL[char.to_s]?
            report[2 + key_index] = val
            key_index += 1
          end
        else
          # Other characters - check KVAL mapping
          if val = KVAL[char.to_s]?
            # Check if this key requires shift modifier
            shifted_chars = ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+", "{", "}", "|", ":", "\"", "~", "<", ">", "?"]
            if shifted_chars.includes?(char.to_s)
              report[0] |= KMOD["shift"]
            end
            report[2 + key_index] = val
            key_index += 1
          end
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
      bytes_written = LibC.write(fd, report, report.size)
      if bytes_written < 0
        errno_val = Errno.value
        if errno_val == Errno::EAGAIN || errno_val == Errno::EWOULDBLOCK
          Log.warn { "Key press write would block - host may not be reading HID reports" }
        else
          Log.error { "Key press write failed with errno: #{errno_val}" }
        end
        return
      elsif bytes_written != report.size
        Log.error { "Key press write incomplete: #{bytes_written}/#{report.size} bytes" }
        return
      end

      # Minimal delay to separate key press and release (optimized for ultra-low latency)
      sleep 0.00001.seconds

      # Send key release (empty report) - exact C pattern: memset(report, 0x0, sizeof(report)); write(fd, report, to_send);
      empty_report = Bytes.new(8, 0_u8)
      Log.debug { "Writing key release: #{empty_report.map { |byte| "%02x" % byte }.join(" ")}" }
      bytes_written = LibC.write(fd, empty_report, empty_report.size)
      if bytes_written < 0
        errno_val = Errno.value
        if errno_val == Errno::EAGAIN || errno_val == Errno::EWOULDBLOCK
          Log.warn { "Key release write would block - host may not be reading HID reports" }
        else
          Log.error { "Key release write failed with errno: #{errno_val}" }
        end
        return
      elsif bytes_written != empty_report.size
        Log.error { "Key release write incomplete: #{bytes_written}/#{empty_report.size} bytes" }
        return
      end

      Log.debug { "HID write completed successfully" }
    ensure
      LibC.close(fd)
    end
  end

  def self.send_text(device_path : String, text : String)
    text.each_char do |char|
      # Clear report first (like C code)
      report = Bytes.new(8, 0_u8)

      # Handle character using KVAL mapping
      char_str = char.to_s

      if char >= 'a' && char <= 'z'
        # Lowercase letters
        report[2] = (char.ord - 'a'.ord + 0x04).to_u8
      elsif char >= 'A' && char <= 'Z'
        # Uppercase letters - add shift and use lowercase equivalent
        report[0] = KMOD["shift"]
        report[2] = (char.downcase.ord - 'a'.ord + 0x04).to_u8
      elsif val = KVAL[char_str]?
        # Use KVAL mapping for numbers, symbols, and special chars
        shifted_chars = ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+", "{", "}", "|", ":", "\"", "~", "<", ">", "?"]
        if shifted_chars.includes?(char_str)
          report[0] = KMOD["shift"]
        end
        report[2] = val
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
        bytes_written = LibC.write(fd, report, report.size)
        if bytes_written < 0
          errno_val = Errno.value
          if errno_val == Errno::EAGAIN || errno_val == Errno::EWOULDBLOCK
            Log.warn { "Text write would block for char '#{char}'" }
          else
            Log.error { "Text write failed for char '#{char}' with errno: #{errno_val}" }
          end
          next
        end

        sleep 0.00001.seconds

        # Send key release (clear report like C code)
        empty_report = Bytes.new(8, 0_u8)
        Log.debug { "Text char '#{char}' release: #{empty_report.map { |byte| "%02x" % byte }.join(" ")}" }
        bytes_written = LibC.write(fd, empty_report, empty_report.size)
        if bytes_written < 0
          errno_val = Errno.value
          if errno_val == Errno::EAGAIN || errno_val == Errno::EWOULDBLOCK
            Log.warn { "Text release write would block for char '#{char}'" }
          else
            Log.error { "Text release write failed for char '#{char}' with errno: #{errno_val}" }
          end
        end

        sleep 0.001.seconds # Minimal delay between characters for ultra-fast typing
      ensure
        LibC.close(fd)
      end
    end
  end
end

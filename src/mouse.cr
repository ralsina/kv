require "file_utils"

# HID Mouse Module for USB Gadget functionality
module HIDMouse
  Log = ::Log.for(self)

  # Rate limiting for mouse reports to prevent host overflow
  @@last_report_time = Time.utc
  @@min_report_interval = 8.milliseconds # 125Hz max rate - optimized for low latency

  # Position debouncing to reduce unnecessary reports
  @@last_x = -1
  @@last_y = -1
  @@position_threshold = 5 # Minimum pixel movement to send new report

  # Mouse button mappings
  MOUSE_BUTTONS = {
    "left"   => 0x01_u8,
    "right"  => 0x02_u8,
    "middle" => 0x04_u8,
  }

  def self.create_mouse_report(buttons : Array(String) = [] of String, x_delta : Int32 = 0, y_delta : Int32 = 0, wheel : Int32 = 0) : Bytes
    # Standard relative mouse report (4 bytes: buttons + X + Y + wheel)
    report = Bytes.new(4, 0_u8)

    # Apply button presses (first byte)
    button_byte = 0_u8
    buttons.each do |button|
      if MOUSE_BUTTONS.has_key?(button)
        button_byte |= MOUSE_BUTTONS[button]
      end
    end
    report[0] = button_byte

    # Clamp deltas to signed 8-bit range (-127 to 127) and convert to unsigned bytes
    # For negative values, we need two's complement representation
    x_clamped = x_delta.clamp(-127, 127)
    y_clamped = y_delta.clamp(-127, 127)
    wheel_clamped = wheel.clamp(-127, 127)

    # Convert signed values to unsigned bytes using two's complement
    x_byte = x_clamped < 0 ? (256 + x_clamped).to_u8 : x_clamped.to_u8
    y_byte = y_clamped < 0 ? (256 + y_clamped).to_u8 : y_clamped.to_u8
    wheel_byte = wheel_clamped < 0 ? (256 + wheel_clamped).to_u8 : wheel_clamped.to_u8

    report[1] = x_byte     # X delta (relative movement)
    report[2] = y_byte     # Y delta (relative movement)
    report[3] = wheel_byte # Wheel delta

    report
  end

  def self.send_mouse_report(device_path : String, report : Bytes)
    # Rate limiting to prevent host overflow errors
    current_time = Time.utc
    time_since_last = current_time - @@last_report_time

    if time_since_last < @@min_report_interval
      sleep_time = @@min_report_interval - time_since_last
      Log.debug { "Rate limiting: sleeping #{sleep_time.total_milliseconds}ms" }
      sleep(sleep_time)
    end

    # Open with O_RDWR and O_NONBLOCK to prevent hanging when host isn't reading
    fd = LibC.open(device_path, LibC::O_RDWR | LibC::O_NONBLOCK, 0o666)
    if fd < 0
      raise "Failed to open HID mouse device #{device_path}"
    end

    begin
      # Send the mouse report
      Log.debug { "Writing mouse report: #{report.map { |byte| "%02x" % byte }.join(" ")}" }
      bytes_written = LibC.write(fd, report, report.size)
      if bytes_written < 0
        errno_val = Errno.value
        if errno_val == Errno::EAGAIN || errno_val == Errno::EWOULDBLOCK
          Log.warn { "Mouse report write would block - host may not be reading HID reports" }
        elsif errno_val == Errno::EOVERFLOW
          Log.warn { "Mouse report overflow (errno -75) - applying aggressive rate limiting" }
          # Double the interval on overflow, up to a maximum of 200ms (5Hz)
          @@min_report_interval = (@@min_report_interval * 2.0).clamp(33.milliseconds, 200.milliseconds)
          Log.debug { "Increased minimum report interval to #{@@min_report_interval.total_milliseconds}ms" }
          # Add longer delay to let host fully recover
          sleep(100.milliseconds)
        else
          Log.error { "Mouse report write failed with errno: #{errno_val}" }
        end
        return
      elsif bytes_written != report.size
        Log.error { "Mouse report write incomplete: #{bytes_written}/#{report.size} bytes" }
        return
      end

      Log.debug { "Mouse HID write completed successfully" }
      @@last_report_time = Time.utc
    ensure
      LibC.close(fd)
    end
  end

  def self.send_mouse_click(device_path : String, button : String)
    # Send button press
    click_report = create_mouse_report([button])
    send_mouse_report(device_path, click_report)

    # Minimal delay for ultra-low latency
    sleep 0.001.seconds

    # Send button release
    release_report = create_mouse_report([] of String)
    send_mouse_report(device_path, release_report)
  end

  def self.send_mouse_press(device_path : String, button : String)
    # Send button press only (no release)
    press_report = create_mouse_report([button])
    send_mouse_report(device_path, press_report)
  end

  def self.send_mouse_release(device_path : String, button : String)
    # Send button release (no buttons pressed)
    release_report = create_mouse_report([] of String)
    send_mouse_report(device_path, release_report)
  end

  def self.send_mouse_move_with_buttons(device_path : String, x_delta : Int32, y_delta : Int32, buttons : Array(String))
    # Send relative movement with current button state preserved
    move_report = create_mouse_report(buttons, x_delta, y_delta)
    send_mouse_report(device_path, move_report)
  end

  def self.send_mouse_wheel(device_path : String, wheel_delta : Int32)
    # Send wheel scroll event
    wheel_report = create_mouse_report([] of String, 0, 0, wheel_delta)
    send_mouse_report(device_path, wheel_report)
  end
end

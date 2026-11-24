# Native CH9329 UART-to-USB-HID bridge support.
#
# Protocol mode frame:
#   57 AB ADDR CMD LEN DATA... CHECKSUM
#
# The default CH9329 address is 0x00 and the default baud rate is 9600.
class CH9329
  Log = ::Log.for(self)

  HEADER_0 = 0x57_u8
  HEADER_1 = 0xAB_u8
  ADDRESS  = 0x00_u8

  CMD_KEYBOARD = 0x02_u8
  CMD_MOUSE_ABSOLUTE = 0x04_u8
  CMD_MOUSE_RELATIVE = 0x05_u8

  @serial : File
  @mutex = Mutex.new

  def initialize(@device : String, baud : Int32 = 9600)
    raise "CH9329 device not found: #{@device}" unless File.exists?(@device)

    configure_serial(baud)
    @serial = File.open(@device, "r+")
    Log.info { "CH9329 serial HID bridge opened: #{@device} @ #{baud} baud" }
  end

  def device : String
    @device
  end

  def keyboard_report(report : Bytes)
    raise ArgumentError.new("CH9329 keyboard reports must contain exactly 8 bytes") unless report.size == 8
    send_frame(CMD_KEYBOARD, report)
  end

  def mouse_report(report : Bytes)
    raise ArgumentError.new("CH9329 mouse reports must contain exactly 4 bytes") unless report.size == 4

    # KV's native relative mouse report is:
    #   buttons, dx, dy, wheel
    # CH9329 expects:
    #   0x01, buttons, dx, dy, wheel
    payload = Bytes.new(5, 0_u8)
    payload[0] = 0x01_u8
    payload[1] = report[0]
    payload[2] = report[1]
    payload[3] = report[2]
    payload[4] = report[3]
    send_frame(CMD_MOUSE_RELATIVE, payload)
  end

  def mouse_absolute_report(report : Bytes)
    raise ArgumentError.new("CH9329 absolute mouse reports must contain exactly 5 bytes") unless report.size == 5

    # KV's absolute report is:
    #   buttons, x_lo, x_hi, y_lo, y_hi
    # CH9329 expects:
    #   0x02, buttons, x_lo, x_hi, y_lo, y_hi, wheel
    payload = Bytes.new(7, 0_u8)
    payload[0] = 0x02_u8
    payload[1] = report[0]
    payload[2] = report[1]
    payload[3] = report[2]
    payload[4] = report[3]
    payload[5] = report[4]
    send_frame(CMD_MOUSE_ABSOLUTE, payload)
  end

  def close
    @mutex.synchronize do
      @serial.close unless @serial.closed?
    end
  rescue ex
    Log.warn { "Failed to close CH9329 #{@device}: #{ex.message}" }
  end

  def self.build_frame(command : UInt8, payload : Bytes) : Bytes
    raise ArgumentError.new("CH9329 payload cannot exceed 255 bytes") if payload.size > 255

    frame = Bytes.new(6 + payload.size, 0_u8)
    frame[0] = HEADER_0
    frame[1] = HEADER_1
    frame[2] = ADDRESS
    frame[3] = command
    frame[4] = payload.size.to_u8
    frame[5, payload.size].copy_from(payload)

    checksum = 0
    frame[0, 5 + payload.size].each { |byte| checksum = (checksum + byte) & 0xff }
    frame[5 + payload.size] = checksum.to_u8
    frame
  end

  private def send_frame(command : UInt8, payload : Bytes)
    frame = CH9329.build_frame(command, payload)

    @mutex.synchronize do
      @serial.write(frame)
      @serial.flush
    end

    Log.debug { "CH9329 TX: #{frame.map { |byte| "%02x" % byte }.join(" ")}" }
  end

  private def configure_serial(baud : Int32)
    unless [1200, 2400, 4800, 9600, 14400, 19200, 38400, 57600, 115200].includes?(baud)
      raise "Unsupported CH9329 baud rate: #{baud}"
    end

    # The CH9329 is normally 9600 8N1.  Configure the Linux tty directly
    # so an existing ttyUSB configuration cannot leave the bridge unusable.
    result = Process.run(
      "stty",
      args: ["-F", @device, baud.to_s, "cs8", "-cstopb", "-parenb", "raw", "-echo", "-ixon", "-ixoff", "-crtscts"],
      output: Process::Redirect::Close,
      error: Process::Redirect::Close
    )

    return if result.success?

    raise "Failed to configure #{@device} with stty"
  end
end

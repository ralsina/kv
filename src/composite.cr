require "file_utils"

# HID Composite Module for USB Gadget functionality (Keyboard + Mouse + Mass Storage)
module HIDComposite
  Log = ::Log.for(self)

  # State for ECM/usb0 and dnsmasq
  @@ecm_enabled : Bool = false
  @@dnsmasq_pid : Int64? = nil
  @@ethernet_ifname : String = "usb0"

  # Class method for ECM enabled state
  def self.ecm_enabled : Bool
    @@ecm_enabled
  end

  # Class method for ethernet interface name
  def self.ethernet_ifname : String
    @@ethernet_ifname
  end

  # Class method for dnsmasq PID
  def self.dnsmasq_pid : Int64?
    @@dnsmasq_pid
  end

  def self.setup_usb_composite_gadget(
    vendor_id : String = "0x16c0",
    product_id : String = "0x048a",
    manufacturer : String = "Gadget",
    product : String = "Radxa KVM Composite",
    serial : String = "fedcba9876543212",
    enable_mass_storage : Bool = false,
    storage_file : String? = nil,
    enable_ecm : Bool = false,
  )
    gadget = "odroidc2_composite" # Composite gadget name
    base = "/sys/kernel/config/usb_gadget/" + gadget

    # Check if USB gadget configfs is available
    unless Dir.exists?("/sys/kernel/config/usb_gadget")
      raise "USB gadget configfs not available. Ensure:\n" +
            "  1. Running on hardware with USB OTG support\n" +
            "  2. configfs is mounted: mount -t configfs none /sys/kernel/config\n" +
            "  3. libcomposite module is loaded: modprobe libcomposite"
    end

    # Check if libcomposite module is loaded
    begin
      lsmod_output = `lsmod | grep libcomposite 2>/dev/null`
      if lsmod_output.strip.empty?
        Log.debug { "libcomposite module not detected, attempting to load it..." }
        result = `modprobe libcomposite 2>&1`
        if $?.success?
          Log.debug { "libcomposite module loaded successfully" }
        else
          Log.debug { "Failed to load libcomposite module: #{result}" }
        end
      else
        Log.debug { "libcomposite module is already loaded" }
      end
    rescue ex
      Log.debug { "Could not check/load libcomposite module: #{ex.message}" }
    end

    # Clean up any existing gadgets first
    cleanup_all_gadgets

    # Give time for cleanup to complete before creating new gadget
    sleep 0.2.seconds

    # Create directories if they don't exist
    FileUtils.mkdir_p "#{base}/strings/0x409"
    FileUtils.mkdir_p "#{base}/configs/c.1/strings/0x409"
    FileUtils.mkdir_p "#{base}/functions/hid.keyboard" # Keyboard function
    FileUtils.mkdir_p "#{base}/functions/hid.mouse"    # Mouse function

    # Create mass storage function if enabled
    if enable_mass_storage && storage_file
      FileUtils.mkdir_p "#{base}/functions/mass_storage.0"
    end

    # Create ECM (Ethernet) function only if enabled
    if enable_ecm
      FileUtils.mkdir_p "#{base}/functions/ecm.usb0"
      # Set MAC addresses (use fixed or random, but must be different)
      dev_mac = "02:00:00:00:00:01"
      host_mac = "02:00:00:00:00:02"
      File.write "#{base}/functions/ecm.usb0/dev_addr", dev_mac
      File.write "#{base}/functions/ecm.usb0/host_addr", host_mac
      # File.write "#{base}/functions/ecm.usb0/ifname", @@ethernet_ifname
    end

    # Write config files
    File.write "#{base}/idVendor", vendor_id
    File.write "#{base}/idProduct", product_id
    File.write "#{base}/bcdDevice", "0x0100"
    File.write "#{base}/bcdUSB", "0x0200"
    File.write "#{base}/strings/0x409/serialnumber", serial
    File.write "#{base}/strings/0x409/manufacturer", manufacturer
    File.write "#{base}/strings/0x409/product", product
    File.write "#{base}/configs/c.1/strings/0x409/configuration", "Config 1 : #{product}"
    File.write "#{base}/configs/c.1/MaxPower", "250"

    # Configure keyboard function
    File.write "#{base}/functions/hid.keyboard/protocol", "1" # Keyboard protocol
    File.write "#{base}/functions/hid.keyboard/subclass", "1"
    File.write "#{base}/functions/hid.keyboard/report_length", "8" # Keyboard reports are 8 bytes

    # HID report descriptor for keyboard
    keyboard_desc = Bytes[
      0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0x05, 0x07, 0x19, 0xE0, 0x29, 0xE7,
      0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x08, 0x81, 0x02, 0x95, 0x01,
      0x75, 0x08, 0x81, 0x03, 0x95, 0x05, 0x75, 0x01, 0x05, 0x08, 0x19, 0x01,
      0x29, 0x05, 0x91, 0x02, 0x95, 0x01, 0x75, 0x03, 0x91, 0x03, 0x95, 0x06,
      0x75, 0x08, 0x15, 0x00, 0x25, 0x65, 0x05, 0x07, 0x19, 0x00, 0x29, 0x65,
      0x81, 0x00, 0xC0,
    ]
    File.open("#{base}/functions/hid.keyboard/report_desc", "wb") { |outf| outf.write(keyboard_desc) }

    # Configure mouse function (using standard relative mouse format)
    File.write "#{base}/functions/hid.mouse/protocol", "2" # Mouse protocol
    File.write "#{base}/functions/hid.mouse/subclass", "1"
    File.write "#{base}/functions/hid.mouse/report_length", "4" # 4 bytes: buttons + X + Y + wheel

    # HID report descriptor for standard relative mouse with wheel support
    mouse_desc = Bytes[
      0x05, 0x01, # Usage Page (Generic Desktop)
      0x09, 0x02, # Usage (Mouse)
      0xa1, 0x01, # Collection (Application)
      0x09, 0x01, # Usage (Pointer)
      0xa1, 0x00, # Collection (Physical)

      # Button definitions (3 buttons)
      0x05, 0x09, # Usage Page (Button)
      0x19, 0x01, # Usage Minimum (1)
      0x29, 0x03, # Usage Maximum (3)
      0x15, 0x00, # Logical Minimum (0)
      0x25, 0x01, # Logical Maximum (1)
      0x95, 0x03, # Report Count (3)
      0x75, 0x01, # Report Size (1)
      0x81, 0x02, # Input (Data,Var,Abs)
      0x95, 0x01, # Report Count (1)
      0x75, 0x05, # Report Size (5)
      0x81, 0x03, # Input (Cnst,Var,Abs) - padding

      # X and Y movement (relative)
      0x05, 0x01, # Usage Page (Generic Desktop)
      0x09, 0x30, # Usage (X)
      0x09, 0x31, # Usage (Y)
      0x15, 0x81, # Logical Minimum (-127)
      0x25, 0x7f, # Logical Maximum (127)
      0x75, 0x08, # Report Size (8)
      0x95, 0x02, # Report Count (2)
      0x81, 0x06, # Input (Data,Var,Rel)

      # Wheel (optional, but helps compatibility)
      0x09, 0x38, # Usage (Wheel)
      0x15, 0x81, # Logical Minimum (-127)
      0x25, 0x7f, # Logical Maximum (127)
      0x75, 0x08, # Report Size (8)
      0x95, 0x01, # Report Count (1)
      0x81, 0x06, # Input (Data,Var,Rel)

      0xc0, # End Collection
      0xc0, # End Collection
    ]
    File.open("#{base}/functions/hid.mouse/report_desc", "wb") { |outf| outf.write(mouse_desc) }

    # Configure mass storage function BEFORE creating symlinks
    mass_storage_enabled = false
    if enable_mass_storage && storage_file
      Log.debug { "Configuring mass storage function (robust sequence)..." }

      # First, ensure the file exists and is accessible
      if File.exists?(storage_file)
        begin
          ro_file = "#{base}/functions/mass_storage.0/lun.0/ro"
          file_file = "#{base}/functions/mass_storage.0/lun.0/file"
          udc_file = "#{base}/UDC"

          # 1. Unbind UDC before reconfiguring mass storage
          if File.exists?(udc_file)
            begin
              File.write(udc_file, "")
              Log.debug { "UDC unbound before mass storage config" }
              sleep 0.2.seconds
            rescue error
              Log.debug { "Could not unbind UDC: #{error.message}" }
            end
          end

          # 2. Set LUN file to empty string before changing ro
          if File.exists?(file_file)
            begin
              File.write(file_file, "")
              Log.debug { "Cleared LUN file before config" }
              sleep 0.2.seconds
            rescue error
              Log.debug { "Could not clear LUN file before config: #{error.message}" }
            end
          end

          # 3. Set ro=1, wait
          if File.exists?(ro_file)
            begin
              File.write(ro_file, "1")
              Log.debug { "Set ro=1 before config" }
              sleep 0.2.seconds
            rescue error
              Log.debug { "Could not set ro=1 before config: #{error.message}" }
            end
          end

          # 4. Set new file, wait
          File.write "#{base}/functions/mass_storage.0/stall", "1"
          File.write "#{base}/functions/mass_storage.0/lun.0/cdrom", "0"
          File.write "#{base}/functions/mass_storage.0/lun.0/removable", "1"
          File.write(file_file, storage_file)
          Log.debug { "Set new LUN file: #{storage_file}" }
          sleep 0.2.seconds

          # 5. Set ro=0, wait
          if File.exists?(ro_file)
            begin
              File.write(ro_file, "0")
              Log.debug { "Set ro=0 after config" }
              sleep 0.2.seconds
            rescue error
              Log.debug { "Could not set ro=0 after config: #{error.message}" }
            end
          end

          Log.debug { "Mass storage configured with file: #{storage_file}" }
          Log.debug { "Mass storage configured with file: #{storage_file}" }
          mass_storage_enabled = true

          # 6. Rebind UDC after configuration
          if File.exists?(udc_file)
            udc_entries = Dir.entries("/sys/class/udc").reject { |e| e == "." || e == ".." }
            if !udc_entries.empty?
              first_udc = udc_entries.first
              begin
                File.write(udc_file, first_udc)
                Log.debug { "UDC rebound after mass storage config: #{first_udc}" }
                sleep 0.2.seconds
              rescue error
                Log.debug { "Could not rebind UDC: #{error.message}" }
              end
            end
          end
        rescue ex
          Log.error { "Failed to configure mass storage: #{ex.message}" }
          Log.error { "   This may happen if the storage file is in use or inaccessible" }
          Log.error { "   Mass storage will be disabled for this session" }

          # Remove the mass storage function directory if configuration failed
          begin
            FileUtils.rm_rf("#{base}/functions/mass_storage.0")
          rescue
            # Ignore cleanup errors
          end
        end
      else
        Log.error { "Storage file does not exist: #{storage_file}" }
      end
    end

    # Create symlinks for both functions
    keyboard_dest = "#{base}/configs/c.1/hid.keyboard"
    unless File.exists?(keyboard_dest) || File.symlink?(keyboard_dest)
      FileUtils.ln_s "#{base}/functions/hid.keyboard", keyboard_dest
    end

    mouse_dest = "#{base}/configs/c.1/hid.mouse"
    unless File.exists?(mouse_dest) || File.symlink?(mouse_dest)
      FileUtils.ln_s "#{base}/functions/hid.mouse", mouse_dest
    end

    # ECM symlink only if enabled
    if enable_ecm
      ecm_dest = "#{base}/configs/c.1/ecm.usb0"
      unless File.exists?(ecm_dest) || File.symlink?(ecm_dest)
        FileUtils.ln_s "#{base}/functions/ecm.usb0", ecm_dest
      end
    end

    # Create mass storage symlink if it was successfully configured
    if mass_storage_enabled
      storage_dest = "#{base}/configs/c.1/mass_storage.0"
      unless File.exists?(storage_dest) || File.symlink?(storage_dest)
        FileUtils.ln_s "#{base}/functions/mass_storage.0", storage_dest
        Log.debug { "Mass storage symlink created" }
      end
    end

    # Find and activate UDC
    udc_entries = Dir.entries("/sys/class/udc").reject { |e| e == "." || e == ".." }
    if udc_entries.empty?
      raise "No USB Device Controller (UDC) found. Ensure USB OTG hardware is available."
    end

    Log.debug { "Available UDCs for composite: #{udc_entries}" }

    # Check current UDC status before writing
    first_udc = udc_entries.first
    udc_file = "#{base}/UDC"

    Log.debug { "Current UDC file content: '#{File.read(udc_file).strip rescue "ERROR"}'" }
    Log.debug { "Writing UDC for composite: #{first_udc}" }

    begin
      File.write(udc_file, first_udc)
      Log.debug { "UDC write completed" }

      # Verify UDC was written correctly
      sleep 0.1.seconds
      actual_udc = File.read(udc_file).strip rescue "ERROR"
      Log.debug { "UDC file after write: '#{actual_udc}'" }
    rescue ex
      Log.debug { "Error writing UDC: #{ex.message}" }
      raise ex
    end

    # Wait for devices to be created with retry mechanism
    keyboard_device = ""
    mouse_device = ""

    # Wait up to 3 seconds for the devices to appear
    (0..10).each do |attempt|
      Log.debug { "Waiting for HID devices... (attempt #{attempt + 1})" }
      sleep 0.3.seconds

      # Check what hidg devices exist
      hidg_devices = Dir.glob("/dev/hidg*").sort

      if hidg_devices.size >= 2
        # Take the last two devices (most recently created)
        keyboard_device = hidg_devices[-2] # Second to last
        mouse_device = hidg_devices[-1]    # Last
        Log.debug { "Found HID devices: keyboard=#{keyboard_device}, mouse=#{mouse_device}" }
        break
      end

      if attempt == 10
        Log.debug { "Available hidg devices after timeout: #{hidg_devices}" }
        raise "Not enough HID devices created. Expected 2, found #{hidg_devices.size}. Available: #{hidg_devices}"
      end
    end

    # ECM/usb0 and dnsmasq are not started by default
    @@ecm_enabled = false
    @@dnsmasq_pid = nil
    {keyboard: keyboard_device, mouse: mouse_device, ethernet: "/dev/usb0", ethernet_ifname: @@ethernet_ifname, dnsmasq_pid: nil}
  end

  # Bring up ECM/usb0 and start dnsmasq (idempotent)
  def self.enable_ecm_interface
    return if @@ecm_enabled
    ethernet_ip = "192.168.7.1/24"
    dhcp_range = "192.168.7.2,192.168.7.10,12h"
    # Wait for /sys/class/net/usb0 to appear (timeout ~3s)
    found_usb0 = false
    10.times do |_|
      if File.exists?("/sys/class/net/#{@@ethernet_ifname}")
        found_usb0 = true
        break
      end
      ::sleep(0.3.seconds)
    end
    if found_usb0
      Log.debug { "Bringing up #{@@ethernet_ifname} and assigning IP #{ethernet_ip}" }
      system("ip link set #{@@ethernet_ifname} up")
      system("ip addr add #{ethernet_ip} dev #{@@ethernet_ifname}")

      # Start dnsmasq for DHCP on usb0
      dnsmasq_args = [
        "--interface=#{@@ethernet_ifname}",
        "--bind-interfaces",
        "--except-interface=lo",
        "--dhcp-range=#{dhcp_range}",
        "--dhcp-authoritative",
        "--no-resolv",
        "--log-facility=/var/log/dnsmasq.usb0.log"
      ]
      begin
        process = Process.new("dnsmasq", dnsmasq_args)
        @@dnsmasq_pid = process.pid
        @@ecm_enabled = true
        Log.debug { "Started dnsmasq for #{@@ethernet_ifname} with pid #{process.pid}" }
      rescue ex
        Log.error { "Failed to start dnsmasq: #{ex.message}" }
      end
    else
      Log.error { "usb0 interface did not appear after gadget activation" }
    end
  end

  # Bring down ECM/usb0 and kill dnsmasq
  def self.disable_ecm_interface
    return unless @@ecm_enabled
    Log.debug { "Tearing down #{@@ethernet_ifname} and killing dnsmasq if running..." }
    # Bring down interface
    system("ip addr flush dev #{@@ethernet_ifname}")
    system("ip link set #{@@ethernet_ifname} down")
    # Kill dnsmasq if pid provided
    if pid = @@dnsmasq_pid
      begin
        Process.signal(Signal::TERM, pid)
        Log.debug { "Killed dnsmasq (pid #{pid})" }
      rescue ex
        Log.error { "Failed to kill dnsmasq: #{ex.message}" }
      end
      @@dnsmasq_pid = nil
    end
    @@ecm_enabled = false
  end

  def self.cleanup_all_gadgets
    # Always bring down ECM/usb0 and kill dnsmasq before removing gadgets
    disable_ecm_interface

    # Clean up any existing gadgets in the system
    gadget_base = "/sys/kernel/config/usb_gadget"
    return unless Dir.exists?(gadget_base)

    begin
      Dir.entries(gadget_base).each do |entry|
        next if entry == "." || entry == ".."
        gadget_path = "#{gadget_base}/#{entry}"
        next unless Dir.exists?(gadget_path)

        Log.debug { "Found existing gadget: #{entry}" }
        cleanup_existing_gadget(gadget_path)
      end
    rescue ex
      Log.debug { "Error during gadget cleanup: #{ex.message}" }
    end
  end

  private def self.cleanup_existing_gadget(base : String)
    # Clean up any existing gadget
    Log.debug { "Cleaning up existing gadget at #{base}" }

    # Step 1: Aggressive kernel workaround for mass storage LUN
    ro_file = "#{base}/functions/mass_storage.0/lun.0/ro"
    mass_storage_file = "#{base}/functions/mass_storage.0/lun.0/file"
    if File.exists?(ro_file)
      begin
        File.write(ro_file, "1")
        sleep 0.2.seconds
      rescue ex
        Log.debug { "Could not set ro=1 before cleanup: #{ex.message}" }
      end
    end
    if File.exists?(mass_storage_file)
      Log.debug { "Clearing mass storage file binding" }
      begin
        File.write(mass_storage_file, "")
        sleep 0.5.seconds
      rescue ex
        Log.debug { "Failed to clear mass storage file: #{ex.message}" }
      end
    end
    if File.exists?(ro_file)
      begin
        File.write(ro_file, "0")
        sleep 0.2.seconds
      rescue ex
        Log.debug { "Could not set ro=0 after cleanup: #{ex.message}" }
      end
    end

    # Step 2: Clear UDC file to disable the gadget
    udc_file = "#{base}/UDC"
    if File.exists?(udc_file)
      Log.debug { "Clearing UDC file: #{udc_file}" }
      begin
        File.write(udc_file, "")
        sleep 0.5.seconds # Give more time for UDC to clear
      rescue ex
        Log.debug { "Failed to clear UDC: #{ex.message}" }
      end
    end

    # Step 2.5: Wait a bit longer to ensure kernel releases resources
    sleep 0.5.seconds

    # Step 3: Remove symlinks if they exist
    ["hid.keyboard", "hid.mouse", "hid.usb0", "hid.usb1", "mass_storage.0"].each do |function_name|
      symlink_path = "#{base}/configs/c.1/#{function_name}"
      if File.exists?(symlink_path) || File.symlink?(symlink_path)
        Log.debug { "Removing symlink: #{symlink_path}" }
        begin
          File.delete(symlink_path)
        rescue ex
          Log.debug { "Failed to remove symlink: #{ex.message}" }
        end
      end
    end

    # Step 4: Remove the entire gadget directory tree
    if Dir.exists?(base)
      Log.debug { "Removing gadget directory: #{base}" }
      begin
        FileUtils.rm_rf(base)
        sleep 0.2.seconds # Give more time for cleanup
      rescue ex
        Log.debug { "Failed to remove gadget directory: #{ex.message}" }
      end
    end

    Log.debug { "Gadget cleanup completed" }
  end
end

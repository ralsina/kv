#!/usr/bin/env crystal

# XKB Keyboard Layout Extractor
# Extracts keyboard layout data from XKB symbol files

require "option_parser"
require "file_utils"

# HID Usage Codes for standard keyboard
HID_CODES = {
  "ESC" => 0x29_u8,
  "F1" => 0x3a_u8, "F2" => 0x3b_u8, "F3" => 0x3c_u8, "F4" => 0x3d_u8,
  "F5" => 0x3e_u8, "F6" => 0x3f_u8, "F7" => 0x40_u8, "F8" => 0x41_u8,
  "F9" => 0x42_u8, "F10" => 0x43_u8, "F11" => 0x44_u8, "F12" => 0x45_u8,
  "F13" => 0x68_u8, "F14" => 0x69_u8, "F15" => 0x6a_u8, "F16" => 0x6b_u8,
  "F17" => 0x6c_u8, "F18" => 0x6d_u8, "F19" => 0x6e_u8, "F20" => 0x6f_u8,
  "F21" => 0x70_u8, "F22" => 0x71_u8, "F23" => 0x72_u8, "F24" => 0x73_u8,
  "PRINT" => 0x46_u8,
  "SCROLL" => 0x47_u8,
  "PAUSE" => 0x48_u8,
  "INSERT" => 0x49_u8,
  "HOME" => 0x4a_u8,
  "PAGEUP" => 0x4b_u8,
  "DELETE" => 0x4c_u8,
  "END" => 0x4d_u8,
  "PAGEDOWN" => 0x4e_u8,
  "RIGHT" => 0x4f_u8,
  "LEFT" => 0x50_u8,
  "DOWN" => 0x51_u8,
  "UP" => 0x52_u8,
  "NUMLOCK" => 0x53_u8,
  "KP_SLASH" => 0x54_u8,
  "KP_ASTERISK" => 0x55_u8,
  "KP_MINUS" => 0x56_u8,
  "KP_PLUS" => 0x57_u8,
  "KP_ENTER" => 0x58_u8,
  "KP_1" => 0x59_u8, "KP_2" => 0x5a_u8, "KP_3" => 0x5b_u8,
  "KP_4" => 0x5c_u8, "KP_5" => 0x5d_u8, "KP_6" => 0x5e_u8,
  "KP_7" => 0x5f_u8, "KP_8" => 0x60_u8, "KP_9" => 0x61_u8,
  "KP_0" => 0x62_u8,
  "KP_DOT" => 0x63_u8,
  "BACKSLASH" => 0x64_u8,
  "APPLICATION" => 0x65_u8,
  "POWER" => 0x66_u8,
  "KP_EQUAL" => 0x67_u8,
}

# Physical key to HID mapping (standard US keyboard)
KEY_TO_HID = {
  "TLDE" => 0x35_u8, # `~
  "AE01" => 0x1e_u8, # 1!
  "AE02" => 0x1f_u8, # 2@
  "AE03" => 0x20_u8, # 3#
  "AE04" => 0x21_u8, # 4$
  "AE05" => 0x22_u8, # 5%
  "AE06" => 0x23_u8, # 6^
  "AE07" => 0x24_u8, # 7&
  "AE08" => 0x25_u8, # 8*
  "AE09" => 0x26_u8, # 9(
  "AE10" => 0x27_u8, # 0)
  "AE11" => 0x2d_u8, # -_
  "AE12" => 0x2e_u8, # +=
  "BKSL" => 0x31_u8, # \|
  "TAB"  => 0x2b_u8,
  "AD01" => 0x04_u8, # Q
  "AD02" => 0x05_u8, # W
  "AD03" => 0x06_u8, # E
  "AD04" => 0x07_u8, # R
  "AD05" => 0x08_u8, # T
  "AD06" => 0x09_u8, # Y
  "AD07" => 0x0a_u8, # U
  "AD08" => 0x0b_u8, # I
  "AD09" => 0x0c_u8, # O
  "AD10" => 0x0d_u8, # P
  "AD11" => 0x2f_u8, # [{
  "AD12" => 0x30_u8, # ]}
  "RTRN" => 0x28_u8, # Enter
  "LCTL" => 0xe0_u8, # Left Ctrl
  "AC01" => 0x16_u8, # A
  "AC02" => 0x17_u8, # S
  "AC03" => 0x18_u8, # D
  "AC04" => 0x19_u8, # F
  "AC05" => 0x1a_u8, # G
  "AC06" => 0x1b_u8, # H
  "AC07" => 0x1c_u8, # J
  "AC08" => 0x1d_u8, # K
  "AC09" => 0x1e_u8, # L
  "AC10" => 0x33_u8, # ;:
  "AC11" => 0x34_u8, # '"'
  # TLDE is repeated above for some layouts
  "LFSH" => 0xe1_u8, # Left Shift
  "BKSP" => 0x2a_u8, # Backspace
  "AB01" => 0x1f_u8, # Z
  "AB02" => 0x20_u8, # X
  "AB03" => 0x21_u8, # C
  "AB04" => 0x22_u8, # V
  "AB05" => 0x23_u8, # B
  "AB06" => 0x24_u8, # N
  "AB07" => 0x25_u8, # M
  "AB08" => 0x26_u8, # ,<
  "AB09" => 0x27_u8, # .>
  "AB10" => 0x28_u8, # /?
  "RTSH" => 0xe5_u8, # Right Shift
  "KPMU" => 0x64_u8, # *
  "LALT" => 0xe2_u8, # Left Alt
  "SPCE" => 0x2c_u8, # Space
  "CAPS" => 0x39_u8, # Caps Lock
  "FK01" => 0x3a_u8, # F1
  "FK02" => 0x3b_u8, # F2
  # ... add more as needed
}

# Special XKB symbols that need mapping
XKB_TO_CHAR = {
  "grave"        => '`',
  "asciitilde"   => '~',
  "exclam"       => '!',
  "at"           => '@',
  "numbersign"   => '#',
  "dollar"       => '$',
  "percent"      => '%',
  "asciicircum"  => '^',
  "ampersand"    => '&',
  "asterisk"     => '*',
  "parenleft"    => '(',
  "parenright"   => ')',
  "minus"        => '-',
  "underscore"   => '_',
  "equal"        => '=',
  "plus"         => '+',
  "bracketleft"  => '[',
  "bracketright" => ']',
  "braceleft"    => '{',
  "braceright"   => '}',
  "backslash"    => '\\',
  "bar"          => '|',
  "semicolon"    => ';',
  "colon"        => ':',
  "apostrophe"   => '\'',
  "quotedbl"     => '"',
  "comma"        => ',',
  "less"         => '<',
  "period"       => '.',
  "greater"      => '>',
  "slash"        => '/',
  "question"     => '?',
}

class XKBLayoutExtractor
  property layout_name : String
  property variant : String?
  property char_to_hid : Hash(Char, UInt8)
  property shift_chars : Set(Char)
  property dead_keys : Hash(String, Array(Char))

  def initialize(@layout_name, @variant = nil)
    @char_to_hid = Hash(Char, UInt8).new
    @shift_chars = Set(Char).new
    @dead_keys = Hash(String, Array(Char)).new
  end

  def extract(file_path : String)
    puts "Extracting layout from: #{file_path}"

    # Use xkbcomp to get the flattened layout with all includes resolved
    File.tempfile("xkbcomp_output") do |temp_file|
      # Generate flattened keymap
      variant_option = variant ? "-variant #{variant}" : ""
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      status = Process.run(
        "bash",
        args: ["-c", "setxkbmap -layout #{layout_name} #{variant_option} -print | xkbcomp -xkb -w 0 - #{temp_file.path}"],
        output: stdout,
        error: stderr
      )

      unless status.success?
        puts "Error: Failed to generate keymap for #{layout_name}#{"(#{variant})" if variant}"
        puts stderr.to_s
        exit 1
      end

      # Parse the generated keymap
      content = File.read(temp_file.path)
      parse_keymap_content(content)
    end
  end

  private def parse_keymap_content(content)
    # Parse key definitions from xkbcomp output
    # Format: key <AE01> { symbols[Group1]= [ 1, exclam, onesuperior, exclamdown ] };
    current_key = nil
    content.each_line do |line|
      line = line.strip
      next if line.empty?

      # Start of key definition
      if line.starts_with?("key <")
        if match = line.match(/key\s+<([^>]+)>/)
          current_key = match[1]
        end
        # Symbols line
      elsif current_key && line.includes?("symbols[Group1]=")
        # Extract everything between the square brackets after symbols[Group1]
        if match = line.match(/symbols\[Group1\]\s*=\s*\[\s*([^\]]+)\s*\]/)
          symbols = match[1].split(",").map(&.strip)
          parse_key_symbols(current_key, symbols)
        end
        current_key = nil
      end
    end
  end

  private def parse_key_symbols(key_name, symbols)
    # Get HID code for this key
    hid_code = KEY_TO_HID[key_name]?
    return unless hid_code

    # Parse symbols: [normal, shift, ...]
    normal = symbols[0]? ? symbols[0].strip : nil
    shifted = symbols[1]? ? symbols[1].strip : nil

    process_normal_symbol(normal, hid_code)
    process_shifted_symbol(shifted, normal, hid_code)
  end

  private def process_normal_symbol(normal, hid_code)
    return unless normal && normal != "void"

    if normal.starts_with?("dead_")
      # Handle dead keys
      dead_type = normal[5..-1]
      @dead_keys[dead_type] = [] of Char unless @dead_keys[dead_type]?
      # We'll mark which characters can be combined with this dead key
    elsif char = xkb_symbol_to_char(normal)
      @char_to_hid[char] = hid_code
    end
  end

  private def process_shifted_symbol(shifted, normal, hid_code)
    return unless shifted && shifted != "void" && shifted != normal

    if char = xkb_symbol_to_char(shifted)
      @char_to_hid[char] = hid_code
      @shift_chars.add(char)
    end
  end

  private def xkb_symbol_to_char(symbol : String) : Char?
    # Remove any level indicators (like _level2)
    symbol = symbol.split("_")[0]

    # Direct character mappings
    if symbol.size == 1 && symbol[0].ascii?
      return symbol[0]
    end

    # Named symbols
    XKB_TO_CHAR[symbol]?
  end

  def generate_yaml : String
    String.build do |io|
      io.puts "name: #{layout_name}#{variant ? "_#{variant}" : ""}"
      io.puts "display_name: \"#{layout_name}#{variant ? " (#{variant})" : ""}\""

      # Letters
      io.puts "letters:"
      ('a'..'z').each do |char|
        if hid_code = @char_to_hid[char]?
          io.puts "  #{char}: \"0x#{hid_code.to_s(16)}\""
        end
      end

      # Numbers and symbols
      io.puts "symbols:"
      @char_to_hid.each do |char, hid_code|
        next if char.ascii_letter?
        # Quote special YAML characters
        char_str = char.to_s
        case char
        when '"'
          # Double quotes need to be escaped in YAML
          io.puts "  \"\\\"\":"
        when '\''
          # Single quotes - use double quotes
          io.puts "  \"'\":"
        when ':'
          # Colon needs to be quoted
          io.puts "  \":\":"
        when '[', ']', '{', '}', ',', '&', '*', '#', '?', '|', '-', '<', '>', '=', '!', '@', '%', '^', '~', '`'
          # Characters that need quoting in YAML
          io.puts "  \"#{char_str}\":"
        else
          # Safe to output directly
          io.puts "  #{char_str}:"
        end
        io.puts "    code: \"0x#{hid_code.to_s(16)}\""
        io.puts "    shift: #{@shift_chars.includes?(char)}"
      end

      # Dead keys
      io.puts "dead_keys: {}"
    end
  end

  def save_to_file(filename : String)
    File.write(filename, generate_yaml)
    puts "Saved layout to: #{filename}"
  end
end

# Main program
layout_name = "us"
variant = nil
output_dir = "."

OptionParser.parse do |parser|
  parser.banner = "Usage: #{PROGRAM_NAME} [options] LAYOUT"

  parser.on("-v VARIANT", "--variant=VARIANT", "Keyboard variant") { |v| variant = v }
  parser.on("-o DIR", "--output=DIR", "Output directory") { |dir| output_dir = dir }
  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end
end

layout_name = ARGV[0]? || layout_name

# Common XKB paths
xkb_paths = [
  "/usr/share/X11/xkb/symbols/#{layout_name}",
  "/usr/local/share/X11/xkb/symbols/#{layout_name}",
]

file_path = xkb_paths.find { |path| File.exists?(path) }

unless file_path
  puts "Error: Could not find XKB symbols file for layout '#{layout_name}'"
  puts "Looked in: #{xkb_paths.join(", ")}"
  exit 1
end

extractor = XKBLayoutExtractor.new(layout_name, variant)
extractor.extract(file_path)

# Generate output filename
output_filename = "#{layout_name}#{variant ? "_#{variant}" : ""}.yaml"
output_path = File.join(output_dir, output_filename)

extractor.save_to_file(output_path)

# Print summary
puts "\nLayout Summary:"
puts "  Layout: #{layout_name}"
puts "  Variant: #{variant || "default"}"
puts "  Characters mapped: #{extractor.char_to_hid.size}"
puts "  Shift characters: #{extractor.shift_chars.size}"
puts "  Dead keys: #{extractor.dead_keys.size}"

# Keyboard Layout Definitions
# Contains keyboard layout mappings for different keyboard layouts

require "yaml"
require "log"
require "baked_file_system"

# Modifier key mappings (same for all layouts)
MODIFIERS = {
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

# Special key mappings (same for all layouts)
SPECIAL_KEYS = {
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
  "f1"  => 0x3a_u8,
  "f2"  => 0x3b_u8,
  "f3"  => 0x3c_u8,
  "f4"  => 0x3d_u8,
  "f5"  => 0x3e_u8,
  "f6"  => 0x3f_u8,
  "f7"  => 0x40_u8,
  "f8"  => 0x41_u8,
  "f9"  => 0x42_u8,
  "f10" => 0x43_u8,
  "f11" => 0x44_u8,
  "f12" => 0x45_u8,
  # Navigation keys
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
  # Other keys
  "num-lock" => 0x53_u8,
  "kp-enter" => 0x58_u8,
}

# US QWERTY Keyboard Layout
# Maps characters to USB HID usage codes
module KeyboardLayouts
  # Baked-in layout files
  class Data
    extend BakedFileSystem
    bake_folder "#{__DIR__}/../layouts"
  end

  struct Layout
    property name : String
    property char_to_hid : Hash(Char, UInt8)
    property shift_chars : Set(Char)
    property modifiers : Hash(String, UInt8)
    property special_keys : Hash(String, UInt8)

    def initialize(@name : String)
      @char_to_hid = Hash(Char, UInt8).new
      @shift_chars = Set(Char).new
      @modifiers = MODIFIERS.dup
      @special_keys = SPECIAL_KEYS.dup
    end

    def add_char(char : Char, hid_code : UInt8, needs_shift : Bool = false)
      @char_to_hid[char] = hid_code
      @shift_chars.add(char) if needs_shift
    end

    def self.from_yaml(yaml_data : String | IO) : Layout
      data = YAML.parse(yaml_data)

      layout = Layout.new(data["display_name"].as_s)

      # Load letters
      if letters = data["letters"]?
        letters.as_h.each do |char, hex_code|
          hex_str = hex_code.as_s
          # Remove "0x" prefix if present
          hex_str = hex_str[2..-1] if hex_str.starts_with?("0x")
          code = hex_str.to_i(16).to_u8
          layout.add_char(char.as_s[0], code)
        end
      end

      # Load symbols
      if symbols = data["symbols"]?
        symbols.as_h.each do |char, symbol_data|
          # Handle both string and integer keys
          char_str = char.as_s?
          if char_str.nil?
            # Integer key - convert to string
            char_str = char.as_i.to_s
          end

          sym = symbol_data.as_h
          hex_str = sym["code"].as_s
          # Remove "0x" prefix if present
          hex_str = hex_str[2..-1] if hex_str.starts_with?("0x")
          code = hex_str.to_i(16).to_u8
          needs_shift = sym["shift"]?.try(&.as_bool) || false
          layout.add_char(char_str[0], code, needs_shift)
        end
      end

      layout
    end
  end

  # Cache for loaded layouts
  @@layout_cache = Hash(String, Layout).new

  # Load layout from baked-in YAML file
  def self.load_layout(name : String) : Layout?
    return @@layout_cache[name] if @@layout_cache.has_key?(name)

    # Try different file naming conventions from the baked data
    filenames = [
      "#{name}.yaml",
      "#{name.downcase}.yaml",
    ]

    filenames.each do |filename|
      begin
        content = Data.get(filename).gets_to_end
        layout = Layout.from_yaml(content)
        @@layout_cache[name] = layout
        return layout
      rescue ex
        # File not found or other error, just try the next one
        Log.error { "Could not load layout #{filename}: #{ex.message}" }
      end
    end

    nil
  end

  # Get layout by name (default to US QWERTY)
  def self.get_layout(name : String? = nil) : Layout
    # Default to "us" if no name is provided
    name_to_load = name || "us"

    # Handle aliases
    case name_to_load.downcase
    when "qwerty", "en-us"
      name_to_load = "us"
    when "azerty"
      name_to_load = "fr"
    end

    # Try to load from YAML
    if layout = load_layout(name_to_load)
      return layout
    end

    # If a specific layout was requested and not found, fallback to 'us'
    if name_to_load != "us"
      Log.warn { "Layout '#{name}' not found, falling back to 'us'." }
      return get_layout("us")
    end

    # If 'us' layout itself fails to load, this is a critical error
    raise "FATAL: Default keyboard layout 'us.yaml' could not be loaded."
  end

  # List available layouts
  def self.available_layouts : Array(String)
    layouts = ["qwerty", "us", "en-US"] # Default layouts

    # Add available YAML layouts from baked data
    layouts += Data.files.select { |file| file.path.ends_with?(".yaml") }.map { |file| file.path[1..-6] }

    layouts.uniq
  end
end
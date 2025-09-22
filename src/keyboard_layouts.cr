# Keyboard Layout Definitions
# Contains keyboard layout mappings for different keyboard layouts

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
  end

  # US QWERTY Layout
  QWERTY = Layout.new("US QWERTY").tap do |layout|
    # Letters (a-z maps to 0x04-0x1d)
    ('a'..'z').each_with_index do |char, i|
      layout.add_char(char, (0x04 + i).to_u8)
    end

    # Numbers and symbols (unshifted)
    layout.add_char('1', 0x1e_u8)
    layout.add_char('2', 0x1f_u8)
    layout.add_char('3', 0x20_u8)
    layout.add_char('4', 0x21_u8)
    layout.add_char('5', 0x22_u8)
    layout.add_char('6', 0x23_u8)
    layout.add_char('7', 0x24_u8)
    layout.add_char('8', 0x25_u8)
    layout.add_char('9', 0x26_u8)
    layout.add_char('0', 0x27_u8)
    layout.add_char('-', 0x2d_u8)
    layout.add_char('=', 0x2e_u8)
    layout.add_char('[', 0x2f_u8)
    layout.add_char(']', 0x30_u8)
    layout.add_char('\\', 0x31_u8)
    layout.add_char(';', 0x33_u8)
    layout.add_char('\'', 0x34_u8)
    layout.add_char('`', 0x35_u8)
    layout.add_char(',', 0x36_u8)
    layout.add_char('.', 0x37_u8)
    layout.add_char('/', 0x38_u8)

    # Shifted symbols
    layout.add_char('!', 0x1e_u8, true)  # Shift + 1
    layout.add_char('@', 0x1f_u8, true)  # Shift + 2
    layout.add_char('#', 0x20_u8, true)  # Shift + 3
    layout.add_char('$', 0x21_u8, true)  # Shift + 4
    layout.add_char('%', 0x22_u8, true)  # Shift + 5
    layout.add_char('^', 0x23_u8, true)  # Shift + 6
    layout.add_char('&', 0x24_u8, true)  # Shift + 7
    layout.add_char('*', 0x25_u8, true)  # Shift + 8
    layout.add_char('(', 0x26_u8, true)  # Shift + 9
    layout.add_char(')', 0x27_u8, true)  # Shift + 0
    layout.add_char('_', 0x2d_u8, true)  # Shift + -
    layout.add_char('+', 0x2e_u8, true)  # Shift + =
    layout.add_char('{', 0x2f_u8, true)  # Shift + [
    layout.add_char('}', 0x30_u8, true)  # Shift + ]
    layout.add_char('|', 0x31_u8, true)  # Shift + \
    layout.add_char(':', 0x33_u8, true)  # Shift + ;
    layout.add_char('"', 0x34_u8, true)  # Shift + '
    layout.add_char('~', 0x35_u8, true)  # Shift + `
    layout.add_char('<', 0x36_u8, true)  # Shift + ,
    layout.add_char('>', 0x37_u8, true)  # Shift + .
    layout.add_char('?', 0x38_u8, true)  # Shift + /
  end

  # Get layout by name (default to QWERTY)
  def self.get_layout(name : String? = nil) : Layout
    if name
      case name.downcase
      when "qwerty", "us", "en-us"
        QWERTY
      else
        QWERTY # Default to QWERTY for now
      end
    else
      QWERTY
    end
  end

  # List available layouts
  def self.available_layouts : Array(String)
    ["qwerty", "us", "en-US"]
  end
end
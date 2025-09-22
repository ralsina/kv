require "spec"
require "log"
require "../src/keyboard_layouts"
require "../src/keyboard"

# Configure logging for tests
Log.setup("*", :error)

describe KeyboardLayouts do
  describe "QWERTY layout" do
    it "loads QWERTY layout correctly" do
      layout = KeyboardLayouts.get_layout("qwerty")
      layout.name.should eq "US QWERTY"
    end

    it "maps lowercase letters correctly" do
      layout = KeyboardLayouts.get_layout("qwerty")

      layout.char_to_hid['a'].should eq 0x04_u8
      layout.char_to_hid['b'].should eq 0x05_u8
      layout.char_to_hid['z'].should eq 0x1d_u8
    end

    it "maps numbers correctly" do
      layout = KeyboardLayouts.get_layout("qwerty")

      layout.char_to_hid['1'].should eq 0x1e_u8
      layout.char_to_hid['2'].should eq 0x1f_u8
      layout.char_to_hid['0'].should eq 0x27_u8
    end

    it "maps symbols correctly" do
      layout = KeyboardLayouts.get_layout("qwerty")

      layout.char_to_hid['-'].should eq 0x2d_u8
      layout.char_to_hid['='].should eq 0x2e_u8
      layout.char_to_hid['['].should eq 0x2f_u8
      layout.char_to_hid[']'].should eq 0x30_u8
    end

    it "identifies shift characters correctly" do
      layout = KeyboardLayouts.get_layout("qwerty")

      layout.shift_chars.should contain('!')
      layout.shift_chars.should contain('@')
      layout.shift_chars.should contain('#')
      layout.shift_chars.should contain('$')
      layout.shift_chars.should contain('%')
      layout.shift_chars.should contain('^')
      layout.shift_chars.should contain('&')
      layout.shift_chars.should contain('*')
      layout.shift_chars.should contain('(')
      layout.shift_chars.should contain(')')
      layout.shift_chars.should contain('_')
      layout.shift_chars.should contain('+')
    end

    it "does NOT mark regular characters as shift" do
      layout = KeyboardLayouts.get_layout("qwerty")

      layout.shift_chars.should_not contain('a')
      layout.shift_chars.should_not contain('1')
      layout.shift_chars.should_not contain('-')
      layout.shift_chars.should_not contain('=')
    end
  end

  describe "layout lookup" do
    it "accepts various QWERTY aliases" do
      KeyboardLayouts.get_layout("qwerty").name.should eq "US QWERTY"
      KeyboardLayouts.get_layout("us").name.should eq "US QWERTY"
      KeyboardLayouts.get_layout("en-US").name.should eq "US QWERTY"
      KeyboardLayouts.get_layout("en-us").name.should eq "US QWERTY"
    end

    it "defaults to QWERTY for unknown layouts" do
      KeyboardLayouts.get_layout("azerty").name.should eq "US QWERTY"
      KeyboardLayouts.get_layout("nonexistent").name.should eq "US QWERTY"
      KeyboardLayouts.get_layout(nil).name.should eq "US QWERTY"
    end

    it "lists available layouts" do
      layouts = KeyboardLayouts.available_layouts
      layouts.should contain("qwerty")
      layouts.should contain("us")
      layouts.should contain("en-US")
    end
  end
end

describe HIDKeyboard do
  describe "keyboard layout management" do
    it "has default QWERTY layout" do
      HIDKeyboard.layout.name.should eq "US QWERTY"
    end

    it "can change layout" do
      original_layout = HIDKeyboard.layout

      # This would normally log the change
      HIDKeyboard.layout = "us"
      HIDKeyboard.layout.name.should eq "US QWERTY"

      # Reset to original
      HIDKeyboard.layout = "qwerty"
    end
  end

  describe "create_keyboard_report" do
    it "creates empty report for no keys" do
      report = HIDKeyboard.create_keyboard_report([] of String)
      report.size.should eq 8
      report.all? { |b| b == 0_u8 }.should be_true
    end

    it "handles single key press" do
      report = HIDKeyboard.create_keyboard_report(["a"])
      report[0].should eq 0x00_u8  # No modifiers
      report[2].should eq 0x04_u8  # 'a' key
      report[3..7].all? { |b| b == 0_u8 }.should be_true
    end

    it "handles multiple key presses" do
      report = HIDKeyboard.create_keyboard_report(["a", "s", "d"])
      report[0].should eq 0x00_u8  # No modifiers
      report[2].should eq 0x04_u8  # 'a' key
      report[3].should eq 0x16_u8  # 's' key
      report[4].should eq 0x07_u8  # 'd' key
      report[5..7].all? { |b| b == 0_u8 }.should be_true
    end

    it "handles modifiers correctly" do
      report = HIDKeyboard.create_keyboard_report(["a"], ["ctrl"])
      report[0].should eq 0x01_u8  # Ctrl modifier
      report[2].should eq 0x04_u8  # 'a' key
    end

    it "handles shift for uppercase letters" do
      report = HIDKeyboard.create_keyboard_report(["A"])
      report[0].should eq 0x02_u8  # Shift modifier
      report[2].should eq 0x04_u8  # 'a' key position
    end

    it "handles shift for symbols" do
      report = HIDKeyboard.create_keyboard_report(["!"])
      report[0].should eq 0x02_u8  # Shift modifier
      report[2].should eq 0x1e_u8  # '1' key position
    end

    it "handles special keys" do
      report = HIDKeyboard.create_keyboard_report(["enter"])
      report[0].should eq 0x00_u8  # No modifiers
      report[2].should eq 0x28_u8  # Enter key
    end

    it "limits to 6 simultaneous keys" do
      keys = ["a", "s", "d", "f", "g", "h", "j", "k"]
      report = HIDKeyboard.create_keyboard_report(keys)

      # First 6 keys should be present
      report[2].should eq 0x04_u8  # 'a'
      report[3].should eq 0x16_u8  # 's'
      report[4].should eq 0x07_u8  # 'd'
      report[5].should eq 0x09_u8  # 'f'
      report[6].should eq 0x0a_u8  # 'g'
      report[7].should eq 0x0b_u8  # 'h'

      # 7th key ('j') should not be present
    end
  end

  describe "character mapping consistency" do
    it "maps all printable ASCII characters" do
      layout = HIDKeyboard.layout

      # Test space (space is handled specially in send_text, not in layout)
      layout.char_to_hid.has_key?(' ').should be_false

      # Test letters a-z
      ('a'..'z').each do |char|
        layout.char_to_hid[char].should_not be_nil
      end

      # Test letters A-Z (should use same codes as lowercase)
      ('A'..'Z').each do |char|
        # Uppercase letters are converted to lowercase in the implementation
        layout.char_to_hid.has_key?(char).should be_false
        layout.char_to_hid[char.downcase].should_not be_nil
      end

      # Test numbers 0-9
      ('0'..'9').each do |char|
        layout.char_to_hid[char].should_not be_nil
      end

      # Test common symbols
      ["-", "=", "[", "]", "\\\\", ";", "'", "`", ",", ".", "/", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+", "{", "}", "|", ":", "\"", "~", "<", ">", "?"].each do |str|
        char = str[0]
        layout.char_to_hid[char].should_not be_nil
      end
    end
  end
end
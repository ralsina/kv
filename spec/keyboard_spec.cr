require "./spec_helper"

describe HIDKeyboard do
  it "creates standard USB HID reports from physical usages" do
    report = HIDKeyboard.create_keyboard_report([0x04_u8], ["left-shift"])

    report.size.should eq(8)
    report[0].should eq(0x02_u8)
    report[2].should eq(0x04_u8)
    report[3].should eq(0_u8)
  end

  it "preserves right Alt for AltGr combinations" do
    report = HIDKeyboard.create_keyboard_report([0x1f_u8], ["right-alt"])

    report[0].should eq(0x40_u8)
    report[2].should eq(0x1f_u8)
  end

  it "supports the non-US backslash usage used by ISO keyboards" do
    report = HIDKeyboard.create_keyboard_report([0x64_u8])

    report[2].should eq(0x64_u8)
  end
end


describe CH9329 do
  it "builds the documented keyboard press frame" do
    frame = CH9329.build_frame(0x02_u8, Bytes[0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00])
    frame.hexstring.should eq("57ab000208000004000000000010")
  end

  it "builds the documented keyboard release frame" do
    frame = CH9329.build_frame(0x02_u8, Bytes.new(8, 0_u8))
    frame.hexstring.should eq("57ab00020800000000000000000c")
  end

  it "builds a relative mouse frame" do
    frame = CH9329.build_frame(0x05_u8, Bytes[0x01, 0x00, 0x0a, 0x00, 0x00])
    frame.hexstring.should eq("57ab00050501000a000017")
  end
end

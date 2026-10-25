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

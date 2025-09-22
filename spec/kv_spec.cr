require "./spec_helper"
require "../src/keyboard_layouts"

# Note: We can't test Main directly without loading main.cr
# which starts the entire application
describe "KV Application" do
  it "has keyboard layouts working" do
    layouts = KeyboardLayouts.available_layouts
    layouts.should contain("qwerty")
    layouts.should contain("fr")
    layouts.should contain("de")
  end
end

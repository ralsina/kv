require "./spec_helper"

describe Main do
  # TODO: Write tests

  it "has a version" do
    Main::VERSION.should match(/\d+\.\d+\.\d+/)
  end
end

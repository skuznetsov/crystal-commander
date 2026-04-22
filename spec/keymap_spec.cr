require "spec"
require "../src/keymap"

describe Commander::Keymap do
  describe ".parse_spec" do
    it "parses simple key" do
      parsed = Commander::Keymap.parse_spec("a")
      parsed.should_not be_nil
      key, mods = parsed.not_nil!
      key.should eq(0) # 'a' code
      mods.should eq(0_u32)
    end

    it "parses ctrl-a" do
      parsed = Commander::Keymap.parse_spec("ctrl-a")
      parsed.should_not be_nil
      key, mods = parsed.not_nil!
      key.should eq(0)
      (mods & Commander::KEYMAP_MOD_CONTROL).should_not eq(0)
    end

    it "parses cmd-shift-x" do
      parsed = Commander::Keymap.parse_spec("cmd-shift-x")
      parsed.should_not be_nil
      key, mods = parsed.not_nil!
      key.should eq(7) # x code
      (mods & Commander::KEYMAP_MOD_COMMAND).should_not eq(0)
      (mods & Commander::KEYMAP_MOD_SHIFT).should_not eq(0)
    end

    it "accepts meta as command" do
      parsed = Commander::Keymap.parse_spec("meta-b")
      parsed.should_not be_nil
      _, mods = parsed.not_nil!
      (mods & Commander::KEYMAP_MOD_COMMAND).should_not eq(0)
    end

    it "accepts opt/alt as option" do
      parsed = Commander::Keymap.parse_spec("opt-up")
      parsed.should_not be_nil
      key, mods = parsed.not_nil!
      key.should eq(126)
      (mods & Commander::KEYMAP_MOD_OPTION).should_not eq(0)
    end

    it "returns nil for unknown key name" do
      Commander::Keymap.parse_spec("cmd-foo").should be_nil
    end

    it "returns nil for unknown modifier" do
      Commander::Keymap.parse_spec("win-a").should be_nil
    end

    it "is case insensitive" do
      parsed = Commander::Keymap.parse_spec("CTRL-A")
      parsed.should_not be_nil
    end
  end

  it "binds and finds command for key+modifiers" do
    km = Commander::Keymap.new
    km.bind_spec("ctrl-c", "copy")
    km.bind_spec("c", "cursor")

    km.command_for(8, Commander::KEYMAP_MOD_CONTROL).should eq("copy") # c is 8?
    km.command_for(8, 0_u32).should eq("cursor")
  end

  it "prefers bindings that require modifiers when modifiers present" do
    km = Commander::Keymap.new
    km.bind_spec("x", "plain-x")
    km.bind_spec("ctrl-x", "ctrl-x")

    # when ctrl pressed, should get the requiring one
    km.command_for(7, Commander::KEYMAP_MOD_CONTROL).should eq("ctrl-x")
  end

  it "no-mod binding does not match when command modifiers are held" do
    km = Commander::Keymap.new
    km.bind_spec("f", "find")

    # ctrl-f should not match the no-mod 'f' binding
    km.command_for(3, Commander::KEYMAP_MOD_CONTROL).should be_nil
  end

  it "iterates bindings" do
    km = Commander::Keymap.new
    km.bind_spec("a", "a-cmd")
    count = 0
    km.each { |_b| count += 1 }
    count.should eq(1)
  end
end

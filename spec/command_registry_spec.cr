require "spec"
require "../src/command_registry"

describe Commander::CommandRegistry do
  it "registers commands and reports them as registered" do
    registry = Commander::CommandRegistry.new
    registry.register("test.cmd", "Test", "desc") { |_ctx| }

    registry.registered?("test.cmd").should be_true
    registry.registered?("missing").should be_false
  end

  it "executes the handler and passes context" do
    registry = Commander::CommandRegistry.new
    received = [] of Commander::CommandContext
    registry.register("run", "Run") do |ctx|
      received << ctx
    end

    ctx = Commander::CommandContext.new(panel_index: 1, argument: "arg1")
    executed = registry.execute("run", ctx)

    executed.should be_true
    received.size.should eq(1)
    received.first.panel_index.should eq(1)
    received.first.argument.should eq("arg1")
  end

  it "returns false for unknown command on execute" do
    registry = Commander::CommandRegistry.new
    registry.execute("nope", Commander::CommandContext.new(0, nil)).should be_false
  end

  it "resolves aliases to target commands" do
    registry = Commander::CommandRegistry.new
    called = false
    registry.register("real", "Real") { |_c| called = true }
    registry.register_alias("alias1", "real")

    registry.registered?("alias1").should be_true
    registry.execute("alias1", Commander::CommandContext.new(0, nil)).should be_true
    called.should be_true
  end

  it "iterates over registered commands" do
    registry = Commander::CommandRegistry.new
    registry.register("c1", "C1") { |_c| }
    registry.register("c2", "C2") { |_c| }

    ids = [] of String
    registry.each { |cmd| ids << cmd.id }
    ids.should contain("c1")
    ids.should contain("c2")
  end

  it "produces command snapshots without exposing handlers" do
    registry = Commander::CommandRegistry.new
    registry.register("snap.cmd", "Snap", "desc", plugin_id: "plug1") { |_c| }

    snaps = registry.to_snapshots
    snaps.size.should eq(1)
    snap = snaps.first
    snap.id.should eq("snap.cmd")
    snap.title.should eq("Snap")
    snap.description.should eq("desc")
    snap.plugin_id.should eq("plug1")
  end
end

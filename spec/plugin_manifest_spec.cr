require "spec"
require "json"
require "../src/plugin_manifest"

describe Commander::PluginManifest do
  it "serializes and deserializes via JSON" do
    manifest = Commander::PluginManifest.new(
      id: "test.plug",
      name: "Test",
      version: "1.0",
      runtime: "lua",
      commands: [Commander::PluginCommandManifest.new("cmd1", "Cmd1")],
      key_bindings: [Commander::PluginKeyBindingManifest.new("ctrl-k", "cmd1")]
    )

    json = manifest.to_json
    restored = Commander::PluginManifest.from_json(json)

    restored.id.should eq("test.plug")
    restored.commands.size.should eq(1)
    restored.key_bindings.size.should eq(1)
  end

  it "produces snapshot with entrypoint_path" do
    manifest = Commander::PluginManifest.new(id: "p1", name: "P", version: "0", runtime: "lua", entrypoint: "main.lua")
    snap = manifest.to_snapshot("/abs/path/main.lua")
    snap.id.should eq("p1")
    snap.entrypoint_path.should eq("/abs/path/main.lua")
    snap.command_ids.should eq([] of String)
  end
end

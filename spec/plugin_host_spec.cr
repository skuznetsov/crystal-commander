require "spec"
require "json"
require "file_utils"
require "../src/plugin_host"

def with_temp_plugin_root
  base = Dir.tempdir
  unique = "cmdr_plug_test_#{Time.utc.to_unix_ms}_#{Random.new.hex(4)}"
  root = File.join(base, unique)
  Dir.mkdir_p(root)
  begin
    yield root
  ensure
    FileUtils.rm_rf(root) rescue nil
  end
end

describe Commander::PluginHost do
  it "loads valid manifest from plugin dir" do
    with_temp_plugin_root do |root|
      plug_dir = File.join(root, "myplug")
      Dir.mkdir(plug_dir)
      manifest_json = {
        "id" => "my.plug",
        "name" => "My",
        "version" => "0.1",
        "api_version" => "0.1",
        "runtime" => "lua",
        "entrypoint" => nil,
        "permissions" => [] of String,
        "commands" => [] of Hash(String, String),
        "key_bindings" => [] of Hash(String, String),
      }.to_json
      File.write(File.join(plug_dir, "plugin.json"), manifest_json)

      host = Commander::PluginHost.new(root)
      host.load_manifests

      host.manifests.size.should eq(1)
      host.manifests.first.id.should eq("my.plug")
      host.load_errors.should be_empty
    end
  end

  it "records error for unsupported runtime" do
    with_temp_plugin_root do |root|
      plug_dir = File.join(root, "bad")
      Dir.mkdir(plug_dir)
      manifest_json = {
        "id" => "bad.plug",
        "name" => "Bad",
        "version" => "0.1",
        "api_version" => "0.1",
        "runtime" => "python", # unsupported
        "entrypoint" => nil,
        "permissions" => [] of String,
        "commands" => [] of Hash(String, String),
        "key_bindings" => [] of Hash(String, String),
      }.to_json
      File.write(File.join(plug_dir, "plugin.json"), manifest_json)

      host = Commander::PluginHost.new(root)
      host.load_manifests

      host.load_errors.any?(&.includes?("unsupported runtime")).should be_true
    end
  end

  it "records error for unsupported permission and invalid key binding" do
    with_temp_plugin_root do |root|
      plug_dir = File.join(root, "badperm")
      Dir.mkdir(plug_dir)
      manifest_json = {
        "id" => "bp.plug",
        "name" => "BP",
        "version" => "0.1",
        "api_version" => "0.1",
        "runtime" => "lua",
        "entrypoint" => nil,
        "permissions" => ["network.evil"],
        "commands" => [{"id" => "doit", "title" => "Do", "description" => ""}],
        "key_bindings" => [{"key" => "ctrl-zzz", "command" => "doit"}],
      }.to_json
      File.write(File.join(plug_dir, "plugin.json"), manifest_json)

      host = Commander::PluginHost.new(root)
      host.load_manifests

      host.load_errors.any?(&.includes?("unsupported permission")).should be_true
      host.load_errors.any?(&.includes?("unsupported key binding")).should be_true
    end
  end

  it "detects duplicate command ids across manifests" do
    with_temp_plugin_root do |root|
      p1 = File.join(root, "p1"); Dir.mkdir(p1)
      p2 = File.join(root, "p2"); Dir.mkdir(p2)

      m1 = {"id" => "p1", "name" => "P1", "version" => "1", "api_version" => "0.1", "runtime" => "lua", "entrypoint" => nil, "permissions" => [] of String,
            "commands" => [{"id" => "dup", "title" => "D", "description" => ""}], "key_bindings" => [] of Hash(String, String)}.to_json
      m2 = {"id" => "p2", "name" => "P2", "version" => "1", "api_version" => "0.1", "runtime" => "lua", "entrypoint" => nil, "permissions" => [] of String,
            "commands" => [{"id" => "dup", "title" => "D", "description" => ""}], "key_bindings" => [] of Hash(String, String)}.to_json
      File.write(File.join(p1, "plugin.json"), m1)
      File.write(File.join(p2, "plugin.json"), m2)

      host = Commander::PluginHost.new(root)
      host.load_manifests

      host.load_errors.any?(&.includes?("duplicate command id")).should be_true
    end
  end
end

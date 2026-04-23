require "spec"
require "socket"
require "../src/automation_server"

private def automation_server_snapshot : Commander::AppSnapshot
  Commander::AppSnapshot.new(
    active_panel: 0,
    panel_count: 0,
    running: true,
    status_text: "Ready",
    dry_run: false,
    plugin_root: "plugins",
    plugins: [] of Commander::PluginSnapshot,
    plugin_runtimes: [] of Commander::PluginRuntimeSnapshot,
    plugin_errors: [] of String,
    commands: [] of Commander::CommandSnapshot,
    pending_operation: nil,
    preview: nil,
    external_view: nil,
    panels: [] of Commander::PanelSnapshot
  )
end

private def temp_socket_path(name : String) : String
  File.join(Dir.tempdir, "commander-#{Process.pid}-#{name}.sock")
end

describe Commander::AutomationServer do
  it "serves one JSON automation command per local Unix socket client" do
    path = temp_socket_path("valid")
    server = Commander::AutomationServer.new(path)
    server.start do |command|
      Commander::AutomationResponse.new(
        ok: true,
        status_text: "ran #{command.command_id}",
        snapshot: automation_server_snapshot
      )
    end

    client = UNIXSocket.new(path)
    client.puts(%({"command_id":"app.help"}))
    response = JSON.parse(client.gets.not_nil!)

    response["ok"].as_bool.should be_true
    response["status_text"].as_s.should eq("ran app.help")
  ensure
    client.try(&.close) rescue nil
    server.try(&.stop) rescue nil
    File.delete(path) if path && File.exists?(path)
  end

  it "returns structured JSON errors for malformed requests" do
    path = temp_socket_path("malformed")
    server = Commander::AutomationServer.new(path)
    server.start do |command|
      Commander::AutomationResponse.new(true, "unexpected", automation_server_snapshot)
    end

    client = UNIXSocket.new(path)
    client.puts(%({"command_id":))
    response = JSON.parse(client.gets.not_nil!)

    response["ok"].as_bool.should be_false
    response["status_text"].as_s.should eq("Automation IPC request failed")
    response["error"].as_s.empty?.should be_false
  ensure
    client.try(&.close) rescue nil
    server.try(&.stop) rescue nil
    File.delete(path) if path && File.exists?(path)
  end

  it "refuses to replace an existing filesystem path" do
    path = temp_socket_path("existing")
    File.write(path, "not a socket")
    server = Commander::AutomationServer.new(path)

    expect_raises(Exception, /already exists/) do
      server.start do |command|
        Commander::AutomationResponse.new(true, command.command_id, automation_server_snapshot)
      end
    end

    File.read(path).should eq("not a socket")
  ensure
    server.try(&.stop) rescue nil
    File.delete(path) if path && File.exists?(path)
  end
end

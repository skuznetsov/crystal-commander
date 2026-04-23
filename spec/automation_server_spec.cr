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
    server.start(-> { automation_server_snapshot }) do |command|
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
    server.start(-> { automation_server_snapshot }) do |command|
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

  it "blocks mutating IPC commands unless dry-run is requested" do
    path = temp_socket_path("policy-block")
    server = Commander::AutomationServer.new(path)
    executed = false
    server.start(-> { automation_server_snapshot }) do |command|
      executed = true
      Commander::AutomationResponse.new(true, command.command_id, automation_server_snapshot)
    end

    client = UNIXSocket.new(path)
    client.puts(%({"command_id":"file.mkdir_named","argument":"/tmp/example"}))
    response = JSON.parse(client.gets.not_nil!)

    response["ok"].as_bool.should be_false
    response["error"].as_s.should contain("dry_run=true")
    executed.should be_false
  ensure
    client.try(&.close) rescue nil
    server.try(&.stop) rescue nil
    File.delete(path) if path && File.exists?(path)
  end

  it "allows mutating IPC commands when dry-run is requested" do
    path = temp_socket_path("policy-dry-run")
    server = Commander::AutomationServer.new(path)
    server.start(-> { automation_server_snapshot }) do |command|
      Commander::AutomationResponse.new(
        ok: true,
        status_text: "dry-run #{command.command_id}",
        snapshot: automation_server_snapshot
      )
    end

    client = UNIXSocket.new(path)
    client.puts(%({"command_id":"file.mkdir_named","argument":"/tmp/example","dry_run":true}))
    response = JSON.parse(client.gets.not_nil!)

    response["ok"].as_bool.should be_true
    response["status_text"].as_s.should eq("dry-run file.mkdir_named")
  ensure
    client.try(&.close) rescue nil
    server.try(&.stop) rescue nil
    File.delete(path) if path && File.exists?(path)
  end

  it "uses the injected IPC policy for command requests" do
    path = temp_socket_path("injected-policy")
    server = Commander::AutomationServer.new(path)
    executed = false
    policy = ->(command : Commander::AutomationCommand) { command.command_id == "safe.command" }
    server.start(-> { automation_server_snapshot }, policy) do |command|
      executed = true
      Commander::AutomationResponse.new(true, command.command_id, automation_server_snapshot)
    end

    client = UNIXSocket.new(path)
    client.puts(%({"kind":"command","command":{"command_id":"file.mkdir_named"}}))
    response = JSON.parse(client.gets.not_nil!)

    response["ok"].as_bool.should be_false
    response["error"].as_s.should contain("dry_run=true")
    executed.should be_false
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

  it "serves structured command request envelopes" do
    path = temp_socket_path("request-command")
    server = Commander::AutomationServer.new(path)
    server.start(-> { automation_server_snapshot }) do |command|
      Commander::AutomationResponse.new(true, "envelope #{command.command_id}", automation_server_snapshot)
    end

    client = UNIXSocket.new(path)
    client.puts(%({"kind":"command","command":{"command_id":"app.help"}}))
    response = JSON.parse(client.gets.not_nil!)

    response["ok"].as_bool.should be_true
    response["status_text"].as_s.should eq("envelope app.help")
  ensure
    client.try(&.close) rescue nil
    server.try(&.stop) rescue nil
    File.delete(path) if path && File.exists?(path)
  end

  it "serves read-only snapshot requests without executing commands" do
    path = temp_socket_path("snapshot")
    server = Commander::AutomationServer.new(path)
    executed = false
    server.start(-> { automation_server_snapshot }) do |command|
      executed = true
      Commander::AutomationResponse.new(true, command.command_id, automation_server_snapshot)
    end

    client = UNIXSocket.new(path)
    client.puts(%({"kind":"snapshot"}))
    response = JSON.parse(client.gets.not_nil!)

    response["ok"].as_bool.should be_true
    response["status_text"].as_s.should eq("Ready")
    response["snapshot"]["status_text"].as_s.should eq("Ready")
    executed.should be_false
  ensure
    client.try(&.close) rescue nil
    server.try(&.stop) rescue nil
    File.delete(path) if path && File.exists?(path)
  end

  it "rejects unknown structured request kinds" do
    path = temp_socket_path("unknown-kind")
    server = Commander::AutomationServer.new(path)
    server.start(-> { automation_server_snapshot }) do |command|
      Commander::AutomationResponse.new(true, command.command_id, automation_server_snapshot)
    end

    client = UNIXSocket.new(path)
    client.puts(%({"kind":"mystery"}))
    response = JSON.parse(client.gets.not_nil!)

    response["ok"].as_bool.should be_false
    response["error"].as_s.should contain("unknown automation request kind")
  ensure
    client.try(&.close) rescue nil
    server.try(&.stop) rescue nil
    File.delete(path) if path && File.exists?(path)
  end
end

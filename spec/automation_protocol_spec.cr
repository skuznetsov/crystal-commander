require "spec"
require "../src/automation_protocol"

describe Commander::AutomationCommand do
  it "parses omitted optional fields with safe defaults" do
    command = Commander::AutomationCommand.from_json(%({"command_id":"app.help"}))

    command.command_id.should eq("app.help")
    command.panel_index.should eq(0)
    command.argument.should be_nil
    command.dry_run.should be_false
  end
end

describe Commander::AutomationRequest do
  it "wraps commands for structured IPC requests" do
    request = Commander::AutomationRequest.from_json(%({"kind":"command","command":{"command_id":"app.help"}}))

    request.kind.should eq("command")
    request.command.not_nil!.command_id.should eq("app.help")
  end

  it "creates read-only state request envelopes" do
    Commander::AutomationRequest.snapshot.to_json.should contain(%("kind":"snapshot"))
    Commander::AutomationRequest.status.to_json.should contain(%("kind":"status"))
  end
end

describe Commander::AutomationPolicy do
  it "allows read-like automation commands by default" do
    command = Commander::AutomationCommand.new("panel.open_path")

    Commander::AutomationPolicy.mutating?(command.command_id).should be_false
    Commander::AutomationPolicy.ipc_allowed?(command).should be_true
  end

  it "requires dry-run for mutating IPC commands" do
    command = Commander::AutomationCommand.new("file.mkdir_named", argument: "/tmp/example")
    dry_run = Commander::AutomationCommand.new("file.mkdir_named", argument: "/tmp/example", dry_run: true)

    Commander::AutomationPolicy.mutating?(command.command_id).should be_true
    Commander::AutomationPolicy.ipc_allowed?(command).should be_false
    Commander::AutomationPolicy.ipc_allowed?(dry_run).should be_true
  end
end

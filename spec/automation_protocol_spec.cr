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

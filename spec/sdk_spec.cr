require "spec"
require "../src/sdk"
require "../src/commander/sdk"

private def sdk_snapshot : Commander::AppSnapshot
  entry = Commander::EntrySnapshot.new(
    name: "README.md",
    size: "1K",
    modified: "Apr 21 22:00",
    path: "/tmp/README.md",
    flags: 0_u32
  )
  panel = Commander::PanelSnapshot.new(
    index: 0,
    path: "/tmp",
    display_path: "/tmp",
    cursor: 0,
    active: true,
    marked_paths: [] of String,
    entries: [entry]
  )
  tab = Commander::TabSnapshot.new(
    index: 0,
    title: "Main",
    active: true,
    panel_count: 1,
    active_panel: 0,
    panel_uris: ["file:///tmp"]
  )

  Commander::AppSnapshot.new(
    active_panel: 0,
    panel_count: 1,
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
    panels: [panel],
    active_tab: 0,
    tabs: [tab]
  )
end

describe Commander::SDK do
  it "constructs and parses automation commands" do
    command = Commander::SDK.command("panel.open_path", panel_index: 1, argument: "/tmp", dry_run: true)

    command.command_id.should eq("panel.open_path")
    command.panel_index.should eq(1)
    command.argument.should eq("/tmp")
    command.dry_run.should be_true

    parsed = Commander::SDK.parse_command_json(%({"command_id":"app.help"}))
    parsed.command_id.should eq("app.help")
    parsed.panel_index.should eq(0)

    sequence = Commander::SDK.parse_command_sequence_json(%([{"command_id":"tab.new"},{"command_id":"tab.next"}]))
    sequence.map(&.command_id).should eq(["tab.new", "tab.next"])
  end

  it "constructs and parses automation request envelopes" do
    command_request = Commander::SDK.command_request("panel.open_path", panel_index: 1, argument: "/tmp")

    command_request.kind.should eq("command")
    command_request.command.not_nil!.command_id.should eq("panel.open_path")
    command_request.command.not_nil!.panel_index.should eq(1)

    Commander::SDK.snapshot_request.kind.should eq("snapshot")
    Commander::SDK.status_request.kind.should eq("status")

    parsed = Commander::SDK.parse_request_json(%({"kind":"status"}))
    parsed.kind.should eq("status")
    parsed.command.should be_nil
  end

  it "exposes VFS helpers without provider I/O" do
    path = Commander::SDK.parse_vfs_uri("sftp://example.com/home/user")

    path.scheme.should eq("sftp")
    path.authority.should eq("example.com")
    Commander::SDK.supported_vfs_schemes.should contain("s3")
    Commander::SDK.default_vfs_registry.dispatch(
      Commander::VirtualFS::Request.new(Commander::VirtualFS::Operation::List, path)
    ).ok.should be_false
  end

  it "exposes plugin and command registries" do
    registry = Commander::SDK.command_registry
    registry.register("sdk.test", "SDK Test") { |_| }

    registry.registered?("sdk.test").should be_true
    Commander::SDK.plugin_host("plugins").root.should eq("plugins")
  end

  it "renders snapshots through SDK-created backends" do
    snapshot = sdk_snapshot
    frame = Commander::SDK.render_workspace(snapshot, Commander::UI::Rect.new(0, 0, 60, 14))
    recording = Commander::SDK.recording_backend
    terminal = Commander::SDK.terminal_grid_backend(60, 14)

    recording.draw(frame)
    terminal.draw(frame)

    Commander::SDK.workspace(snapshot).tabs.first.title.should eq("Main")
    recording.last_commands.should eq(frame.commands)
    terminal.rendered_lines.join("\n").should contain("README.md")
  end
end

require "spec"
require "../src/ui_api"

describe Commander::UI do
  it "builds a backend-neutral workspace view from snapshots" do
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
    command = Commander::CommandSnapshot.new("file.view", "View", "View selected file", nil)
    snapshot = Commander::AppSnapshot.new(
      active_panel: 0,
      panel_count: 1,
      running: true,
      status_text: "Ready",
      dry_run: false,
      plugin_root: "plugins",
      plugins: [] of Commander::PluginSnapshot,
      plugin_runtimes: [] of Commander::PluginRuntimeSnapshot,
      plugin_errors: [] of String,
      commands: [command],
      pending_operation: nil,
      preview: nil,
      external_view: nil,
      panels: [panel]
    )

    view = Commander::UI.workspace(snapshot)
    view.active_panel.should eq(0)
    view.status_text.should eq("Ready")
    view.command_ids.should eq(["file.view"])
    view.panels.first.selected_entry.not_nil!.name.should eq("README.md")
    snapshot.panels.first.uri.should eq("file:///tmp")
    snapshot.panels.first.entries.first.uri.should eq("file:///tmp/README.md")
    snapshot.to_json.should contain(%("uri":"file:///tmp"))
    snapshot.to_json.should contain(%("uri":"file:///tmp/README.md"))
  end

  it "defines viewer and external view request models without backend dependencies" do
    theme = Commander::UI::Theme.new
    buffer = Commander::UI::TextBuffer.new("README.md", "# Title\n", readonly: true)
    request = Commander::UI::ExternalViewRequest.new("/tmp/README.md")

    theme.accent.should eq("cyan")
    buffer.readonly.should be_true
    request.readonly.should be_true
  end

  it "defines backend-neutral draw frames and normalized events" do
    theme = Commander::UI::Theme.new
    bounds = Commander::UI::Rect.new(0, 0, 80, 24)
    commands = [
      Commander::UI::DrawCommand.fill_rect(bounds, theme.background),
      Commander::UI::DrawCommand.new(Commander::UI::DrawKind::Image, rect: bounds, metadata: {"source" => "icon"}),
    ]
    frame = Commander::UI::DrawFrame.new(bounds, theme, commands)
    backend = Commander::UI::RecordingBackend.new(events: [Commander::UI::UIEvent.new(Commander::UI::EventKind::Wakeup)])

    backend.draw(frame)
    backend.last_commands.should eq(commands)
    backend.poll_event.not_nil!.kind.should eq(Commander::UI::EventKind::Wakeup)
    backend.poll_event.should be_nil
  end

  it "renders workspace snapshots into identical draw command streams for swappable backends" do
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
    snapshot = Commander::AppSnapshot.new(
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

    view = Commander::UI.workspace(snapshot)
    frame = Commander::UI::WorkspaceRenderer.render(view, Commander::UI::Rect.new(0, 0, 80, 24))
    appkit_stub = Commander::UI::RecordingBackend.new("appkit-stub")
    terminal_stub = Commander::UI::RecordingBackend.new("terminal-stub")

    appkit_stub.draw(frame)
    terminal_stub.draw(frame)

    view.tabs.first.title.should eq("Main")
    frame.commands.map(&.kind).should contain(Commander::UI::DrawKind::Text)
    frame.commands.map(&.style).should contain("file-panel-0.list.selection")
    frame.commands.compact_map(&.text).should contain("README.md")
    appkit_stub.last_commands.should eq(terminal_stub.last_commands)
    appkit_stub.last_commands.should eq(frame.commands)
  end

  it "builds a retained workspace widget tree with tabs, split panels, and list rows" do
    left_entry = Commander::EntrySnapshot.new(
      name: "left.txt",
      size: "10B",
      modified: "Apr 21 22:00",
      path: "/tmp/left.txt",
      flags: 0_u32
    )
    right_entry = Commander::EntrySnapshot.new(
      name: "right.txt",
      size: "20B",
      modified: "Apr 21 22:01",
      path: "/tmp/right.txt",
      flags: 0_u32
    )
    left = Commander::PanelSnapshot.new(
      index: 0,
      path: "/tmp",
      display_path: "/tmp",
      cursor: 0,
      active: true,
      marked_paths: [] of String,
      entries: [left_entry]
    )
    right = Commander::PanelSnapshot.new(
      index: 1,
      path: "/var",
      display_path: "/var",
      cursor: 0,
      active: false,
      marked_paths: [] of String,
      entries: [right_entry]
    )
    tab = Commander::TabSnapshot.new(
      index: 0,
      title: "Main",
      active: true,
      panel_count: 2,
      active_panel: 0,
      panel_uris: ["file:///tmp", "file:///var"]
    )
    snapshot = Commander::AppSnapshot.new(
      active_panel: 0,
      panel_count: 2,
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
      panels: [left, right],
      active_tab: 0,
      tabs: [tab]
    )

    widget = Commander::UI::WorkspaceWidget.new(Commander::UI.workspace(snapshot))
    frame = widget.render_frame(Commander::UI::Rect.new(0, 0, 100, 30))

    widget.children.map(&.id).should eq(["tab-bar", "workspace-panels", "status-bar"])
    frame.commands.compact_map(&.text).should contain("left.txt")
    frame.commands.compact_map(&.text).should contain("right.txt")
    frame.commands.map(&.style).should contain("tab-bar.active")
    frame.commands.map(&.style).should contain("file-panel-0.list.selection")
  end

  it "projects external viewer requests from app snapshots" do
    external_view = Commander::ExternalViewSnapshot.new("/tmp/README.md", true, nil)
    snapshot = Commander::AppSnapshot.new(
      active_panel: 0,
      panel_count: 1,
      running: true,
      status_text: "External view planned",
      dry_run: false,
      plugin_root: "plugins",
      plugins: [] of Commander::PluginSnapshot,
      plugin_runtimes: [] of Commander::PluginRuntimeSnapshot,
      plugin_errors: [] of String,
      commands: [] of Commander::CommandSnapshot,
      pending_operation: nil,
      preview: nil,
      external_view: external_view,
      panels: [] of Commander::PanelSnapshot
    )

    view = Commander::UI.workspace(snapshot)
    view.external_view.not_nil!.path.should eq("/tmp/README.md")
    view.external_view.not_nil!.readonly.should be_true
  end
end

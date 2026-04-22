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
      panels: [panel]
    )

    view = Commander::UI.workspace(snapshot)
    view.active_panel.should eq(0)
    view.status_text.should eq("Ready")
    view.command_ids.should eq(["file.view"])
    view.panels.first.selected_entry.not_nil!.name.should eq("README.md")
  end

  it "defines viewer and external view request models without backend dependencies" do
    theme = Commander::UI::Theme.new
    buffer = Commander::UI::TextBuffer.new("README.md", "# Title\n", readonly: true)
    request = Commander::UI::ExternalViewRequest.new("/tmp/README.md")

    theme.accent.should eq("cyan")
    buffer.readonly.should be_true
    request.readonly.should be_true
  end
end

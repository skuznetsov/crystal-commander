require "./automation_protocol"
require "./command_registry"
require "./plugin_host"
require "./plugin_manifest"
require "./plugin_runtime"
require "./snapshots"
require "./ui_api"
require "./virtual_fs"

module Commander
  module SDK
    VERSION = "0.1.0"

    def self.command(command_id : String, panel_index : Int32 = 0, argument : String? = nil, dry_run : Bool = false) : AutomationCommand
      AutomationCommand.new(command_id, panel_index, argument, dry_run)
    end

    def self.parse_command_json(json : String) : AutomationCommand
      AutomationCommand.from_json(json)
    end

    def self.parse_command_sequence_json(json : String) : Array(AutomationCommand)
      Array(AutomationCommand).from_json(json)
    end

    def self.command_registry : CommandRegistry
      CommandRegistry.new
    end

    def self.plugin_host(root : String = "plugins") : PluginHost
      PluginHost.new(root)
    end

    def self.parse_vfs_uri(uri : String) : VirtualFS::VirtualPath
      VirtualFS::VirtualPath.parse(uri)
    end

    def self.default_vfs_registry : VirtualFS::Registry
      VirtualFS::Registry.default
    end

    def self.supported_vfs_schemes : Set(String)
      VirtualFS::SUPPORTED_SCHEMES.dup
    end

    def self.workspace(snapshot : AppSnapshot) : UI::WorkspaceView
      UI.workspace(snapshot)
    end

    def self.render_workspace(snapshot : AppSnapshot, bounds : UI::Rect, theme : UI::Theme = UI::Theme.new) : UI::DrawFrame
      UI::WorkspaceRenderer.render(workspace(snapshot), bounds, theme)
    end

    def self.recording_backend(name : String = "recording", theme : UI::Theme = UI::Theme.new, events : Array(UI::UIEvent) = [] of UI::UIEvent) : UI::RecordingBackend
      UI::RecordingBackend.new(name, theme, events)
    end

    def self.terminal_grid_backend(width : Int32, height : Int32, name : String = "terminal-grid", theme : UI::Theme = UI::Theme.new, events : Array(UI::UIEvent) = [] of UI::UIEvent) : UI::TerminalGridBackend
      UI::TerminalGridBackend.new(width, height, name, theme, events)
    end
  end
end

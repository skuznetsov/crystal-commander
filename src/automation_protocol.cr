require "json"
require "./snapshots"

module Commander
  module AutomationPolicy
    MUTATING_COMMAND_IDS = Set{
      "file.copy",
      "file.copy_to",
      "file.renmov",
      "file.renmov_to",
      "file.mkdir",
      "file.mkdir_named",
      "file.delete",
      "file.delete_plan",
      "file.operation_execute",
      "vfs.execute_pending_action",
    }

    MUTATING_PREFIXES = ["file.", "vfs.execute_"]

    def self.mutating?(command_id : String) : Bool
      return true if MUTATING_COMMAND_IDS.includes?(command_id)

      MUTATING_PREFIXES.any? { |prefix| command_id.starts_with?(prefix) }
    end

    def self.ipc_allowed?(command : AutomationCommand) : Bool
      return true unless mutating?(command.command_id)

      command.dry_run
    end

    def self.ipc_denial(command : AutomationCommand) : String
      "Automation IPC requires dry_run=true for mutating command: #{command.command_id}"
    end
  end

  struct AutomationCommand
    include JSON::Serializable

    getter command_id : String
    getter panel_index : Int32 = 0
    getter argument : String? = nil
    getter dry_run : Bool = false

    def initialize(@command_id : String, @panel_index : Int32 = 0, @argument : String? = nil, @dry_run : Bool = false)
    end
  end

  struct AutomationRequest
    include JSON::Serializable

    getter kind : String = "command"
    getter command : AutomationCommand?

    def initialize(@kind : String = "command", @command : AutomationCommand? = nil)
    end

    def self.command(command : AutomationCommand) : AutomationRequest
      new("command", command)
    end

    def self.snapshot : AutomationRequest
      new("snapshot")
    end

    def self.status : AutomationRequest
      new("status")
    end
  end

  struct AutomationResponse
    include JSON::Serializable

    getter ok : Bool
    getter status_text : String
    getter error : String?
    getter snapshot : AppSnapshot

    def initialize(@ok : Bool, @status_text : String, @snapshot : AppSnapshot, @error : String? = nil)
    end

    def self.snapshot(snapshot : AppSnapshot) : AutomationResponse
      new(true, snapshot.status_text, snapshot)
    end

    def self.error(message : String, snapshot : AppSnapshot? = nil) : AutomationResponse
      snapshot ||= AppSnapshot.new(
        active_panel: 0,
        panel_count: 0,
        running: false,
        status_text: message,
        dry_run: false,
        plugin_root: "",
        plugins: [] of PluginSnapshot,
        plugin_runtimes: [] of PluginRuntimeSnapshot,
        plugin_errors: [] of String,
        commands: [] of CommandSnapshot,
        pending_operation: nil,
        preview: nil,
        external_view: nil,
        panels: [] of PanelSnapshot
      )
      new(false, message, snapshot, message)
    end
  end
end

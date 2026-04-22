require "./plugin_manifest"
require "./snapshots"

module Commander
  struct PluginRuntimeRequest
    include JSON::Serializable

    getter command_id : String
    getter plugin_id : String
    getter entrypoint_path : String?
    getter context : AppSnapshot

    def initialize(@command_id : String, @plugin_id : String, @entrypoint_path : String?, @context : AppSnapshot)
    end
  end

  struct PluginRuntimeResponse
    include JSON::Serializable

    getter ok : Bool
    getter status_text : String?
    getter error : String?

    def initialize(@ok : Bool, @status_text : String? = nil, @error : String? = nil)
    end
  end

  record PluginRuntimeContext,
    app_snapshot : AppSnapshot

  abstract class PluginRuntime
    abstract def runtime_name : String
    abstract def enabled? : Bool
    abstract def load(manifest : PluginManifest) : Nil
    abstract def execute(request : PluginRuntimeRequest) : PluginRuntimeResponse
  end

  class LuaPluginRuntime < PluginRuntime
    def initialize(@enabled : Bool = false)
    end

    def runtime_name : String
      "lua"
    end

    def enabled? : Bool
      @enabled
    end

    def load(manifest : PluginManifest) : Nil
      # Lua runtime is intentionally not embedded yet. Loading is metadata-only.
    end

    def execute(request : PluginRuntimeRequest) : PluginRuntimeResponse
      unless @enabled
        return PluginRuntimeResponse.new(false, error: "Lua runtime is disabled")
      end

      PluginRuntimeResponse.new(false, error: "Lua runtime is not implemented yet for #{request.command_id}")
    end
  end

  class SubprocessPluginRuntime < PluginRuntime
    def initialize(@enabled : Bool = false)
    end

    def runtime_name : String
      "subprocess"
    end

    def enabled? : Bool
      @enabled
    end

    def load(manifest : PluginManifest) : Nil
      # Subprocess runtime is intentionally not enabled yet.
    end

    def execute(request : PluginRuntimeRequest) : PluginRuntimeResponse
      unless @enabled
        return PluginRuntimeResponse.new(false, error: "Subprocess runtime is disabled")
      end

      PluginRuntimeResponse.new(false, error: "Subprocess runtime is not implemented yet for #{request.command_id}")
    end
  end
end

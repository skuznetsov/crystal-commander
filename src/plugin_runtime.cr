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
    LUA_CANDIDATES = ["lua", "lua5.4", "luajit"]
    PATH_SEPARATOR = ":"

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

      entrypoint = request.entrypoint_path
      unless entrypoint && File.file?(entrypoint)
        return PluginRuntimeResponse.new(false, error: "Lua entrypoint not found")
      end

      lua = lua_executable
      unless lua
        return PluginRuntimeResponse.new(false, error: "Lua executable not found; set COMMANDER_LUA_BIN")
      end

      script = lua_wrapper(request, entrypoint)
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      status = Process.run(lua, input: IO::Memory.new(script), output: stdout, error: stderr)
      unless status.success?
        message = stderr.to_s.strip
        message = "Lua command failed with exit #{status.exit_code}" if message.empty?
        return PluginRuntimeResponse.new(false, error: message)
      end

      text = stdout.to_s.strip
      text = "Lua command executed: #{request.command_id}" if text.empty?
      PluginRuntimeResponse.new(true, status_text: text)
    end

    private def lua_executable : String?
      configured = ENV["COMMANDER_LUA_BIN"]?
      return configured if configured && executable_command?(configured)

      LUA_CANDIDATES.each do |candidate|
        return candidate if executable_command?(candidate)
      end
      nil
    end

    private def executable_command?(command : String) : Bool
      if command.includes?("/")
        return executable_file?(command)
      end

      ENV["PATH"].split(PATH_SEPARATOR).any? do |dir|
        path = File.join(dir, command)
        executable_file?(path)
      end
    end

    private def executable_file?(path : String) : Bool
      LibC.access(path, 1) == 0 && !File.directory?(path)
    end

    private def lua_wrapper(request : PluginRuntimeRequest, entrypoint : String) : String
      active_panel = request.context.active_panel
      <<-LUA
      local __commands = {}
      local __status = nil

      commander = {}

      function commander.command(id, fn)
        __commands[id] = fn
      end

      function commander.status(text)
        __status = tostring(text or "")
      end

      local ok_load, load_err = pcall(dofile, #{lua_string(entrypoint)})
      if not ok_load then
        io.stderr:write(tostring(load_err))
        os.exit(2)
      end

      local fn = __commands[#{lua_string(request.command_id)}]
      if fn == nil then
        io.stderr:write("Lua command not registered: " .. #{lua_string(request.command_id)})
        os.exit(3)
      end

      local ctx = {
        command_id = #{lua_string(request.command_id)},
        plugin_id = #{lua_string(request.plugin_id)},
        active_panel = #{active_panel}
      }

      local ok_exec, exec_err = pcall(fn, ctx)
      if not ok_exec then
        io.stderr:write(tostring(exec_err))
        os.exit(4)
      end

      if __status ~= nil then
        io.write(__status)
      end
      LUA
    end

    private def lua_string(value : String) : String
      escaped = value
        .gsub("\\", "\\\\")
        .gsub("\"", "\\\"")
        .gsub("\n", "\\n")
        .gsub("\r", "\\r")
      "\"#{escaped}\""
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

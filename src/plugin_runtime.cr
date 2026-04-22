require "./plugin_manifest"
require "./snapshots"
require "./virtual_fs"

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
    getter actions : Array(PluginRuntimeAction)

    def initialize(@ok : Bool, @status_text : String? = nil, @error : String? = nil, @actions : Array(PluginRuntimeAction) = [] of PluginRuntimeAction)
    end
  end

  struct PluginRuntimeAction
    include JSON::Serializable

    getter kind : String
    getter operation : String
    getter uri : String
    getter target_uri : String?

    def initialize(@kind : String, @operation : String, @uri : String, @target_uri : String? = nil)
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

      plugin = request.context.plugins.find { |snapshot| snapshot.id == request.plugin_id }
      script = lua_wrapper(request, entrypoint, plugin)
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      status = Process.run(lua, input: IO::Memory.new(script), output: stdout, error: stderr)
      unless status.success?
        message = stderr.to_s.strip
        message = "Lua command failed with exit #{status.exit_code}" if message.empty?
        return PluginRuntimeResponse.new(false, error: message)
      end

      parsed = parse_lua_stdout(stdout.to_s, request.command_id)
      PluginRuntimeResponse.new(true, status_text: parsed[0], actions: parsed[1])
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

    private def lua_wrapper(request : PluginRuntimeRequest, entrypoint : String, plugin : PluginSnapshot?) : String
      active_panel = request.context.active_panel
      panel = request.context.panels.find { |snapshot| snapshot.index == active_panel }
      <<-LUA
      local __commands = {}
      local __status = nil
      local __actions = {}

      commander = {}

      function commander.command(id, fn)
        __commands[id] = fn
      end

      function commander.status(text)
        __status = tostring(text or "")
      end

      local __vfs_allowed = #{lua_vfs_allowed_schemes(plugin)}

      commander.vfs = {}

      function commander.vfs.allowed_schemes()
        local schemes = {}
        for scheme, _ in pairs(__vfs_allowed) do
          table.insert(schemes, scheme)
        end
        table.sort(schemes)
        return schemes
      end

      function commander.vfs.request(operation, uri, target_uri)
        local item, err = commander.vfs.parse(uri)
        if err ~= nil then
          return nil, err
        end

        local target = nil
        if target_uri ~= nil then
          local target_item, target_err = commander.vfs.parse(target_uri)
          if target_err ~= nil then
            return nil, target_err
          end
          target = target_item.uri
        end

        local action = { kind = "vfs", operation = tostring(operation or ""), uri = item.uri, target_uri = target }
        table.insert(__actions, action)
        return action, nil
      end

      function commander.vfs.parse(uri)
        local value = tostring(uri or "")
        local scheme, rest = string.match(value, "^([%w%+%-%.]+)://(.*)$")
        if scheme == nil then
          scheme = "file"
          rest = value
        end

        if not __vfs_allowed[scheme] then
          return nil, { code = "PermissionDenied", message = "VFS scheme is not permitted for this plugin" }
        end

        if scheme == "file" then
          local path = rest
          if string.match(value, "^file://") then
            local _, file_path = string.match(rest, "^([^/]*)(/.*)$")
            path = file_path or rest
          end
          return { scheme = "file", authority = nil, path = path, uri = value }, nil
        end

        if scheme ~= "ssh" and scheme ~= "sftp" and scheme ~= "s3" then
          return nil, { code = "UnsupportedScheme", message = "VFS scheme is unsupported" }
        end

        local authority, path = string.match(rest, "^([^/]*)(/.*)$")
        if authority == nil then
          authority = rest
          path = "/"
        end
        return { scheme = scheme, authority = authority, path = path, uri = value }, nil
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
        active_panel = #{active_panel},
        panel = #{lua_panel(panel)}
      }

      local ok_exec, exec_err = pcall(fn, ctx)
      if not ok_exec then
        io.stderr:write(tostring(exec_err))
        os.exit(4)
      end

      if __status ~= nil then
        io.write(__status)
      end
      if #__actions > 0 then
        io.write("\\n__COMMANDER_ACTIONS__")
        for _, action in ipairs(__actions) do
          io.write("\\n" .. action.operation .. "\\t" .. action.uri .. "\\t" .. (action.target_uri or ""))
        end
      end
      LUA
    end

    private def parse_lua_stdout(output : String, command_id : String) : Tuple(String, Array(PluginRuntimeAction))
      lines = output.lines
      marker_index = lines.index("__COMMANDER_ACTIONS__")
      unless marker_index
        text = output.strip
        text = "Lua command executed: #{command_id}" if text.empty?
        return {text, [] of PluginRuntimeAction}
      end

      status_text = lines[0, marker_index].join("\n").strip
      status_text = "Lua command executed: #{command_id}" if status_text.empty?
      actions = lines[(marker_index + 1)..].map do |line|
        operation, uri, target_uri = line.split("\t", 3)
        PluginRuntimeAction.new("vfs", operation, uri, target_uri.empty? ? nil : target_uri)
      end
      {status_text, actions}
    end

    private def lua_string(value : String) : String
      escaped = value
        .gsub("\\", "\\\\")
        .gsub("\"", "\\\"")
        .gsub("\n", "\\n")
        .gsub("\r", "\\r")
      "\"#{escaped}\""
    end

    private def lua_vfs_allowed_schemes(plugin : PluginSnapshot?) : String
      return "{}" unless plugin

      allowed = plugin.permissions.select { |permission| permission.starts_with?("vfs.read:") }
      return "{}" if allowed.empty?

      schemes = allowed.flat_map do |permission|
        value = permission.split(":", 2)[1]
        value == "*" ? Commander::VirtualFS::SUPPORTED_SCHEMES.to_a : [value]
      end.to_set

      entries = Commander::VirtualFS::SUPPORTED_SCHEMES
        .select { |scheme| schemes.includes?(scheme) }
        .map { |scheme| "[#{lua_string(scheme)}] = true" }
      "{#{entries.join(", ")}}"
    end

    private def lua_panel(panel : PanelSnapshot?) : String
      return "nil" unless panel

      selected = if panel.cursor >= 0 && panel.cursor < panel.entries.size
                   panel.entries[panel.cursor]
                 end

      entries = panel.entries.map { |entry| lua_entry(entry) }
      marked_paths = panel.marked_paths.map { |path| lua_string(path) }
      <<-LUA
      {
        index = #{panel.index},
        path = #{lua_string(panel.path)},
        uri = #{lua_string(panel.uri)},
        display_path = #{lua_string(panel.display_path)},
        cursor = #{panel.cursor},
        active = #{panel.active ? "true" : "false"},
        marked_paths = #{lua_array(marked_paths)},
        entries = #{lua_array(entries)},
        selected_entry = #{selected ? lua_entry(selected) : "nil"}
      }
      LUA
    end

    private def lua_entry(entry : EntrySnapshot) : String
      <<-LUA
      {
        name = #{lua_string(entry.name)},
        size = #{lua_string(entry.size)},
        modified = #{lua_string(entry.modified)},
        path = #{lua_string(entry.path)},
        uri = #{lua_string(entry.uri)},
        flags = #{entry.flags}
      }
      LUA
    end

    private def lua_array(values : Array(String)) : String
      "{#{values.join(", ")}}"
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

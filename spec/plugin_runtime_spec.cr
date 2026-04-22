require "spec"
require "file_utils"
require "../src/plugin_runtime"

private def runtime_snapshot_context(active_panel : Int32 = 0) : Commander::AppSnapshot
  Commander::AppSnapshot.new(
    active_panel: active_panel,
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
    panels: [] of Commander::PanelSnapshot
  )
end

private def with_lua_plugin_file(source : String)
  root = File.join(Dir.tempdir, "cmdr_lua_runtime_#{Random.new.hex(4)}")
  Dir.mkdir_p(root)
  path = File.join(root, "main.lua")
  File.write(path, source)
  begin
    yield path
  ensure
    FileUtils.rm_rf(root) rescue nil
  end
end

private def find_lua_binary : String?
  configured = ENV["COMMANDER_LUA_BIN"]?
  return configured if configured && executable_file?(configured)

  candidates = ["lua", "lua5.4", "luajit"]
  ENV["PATH"].split(":").each do |dir|
    candidates.each do |candidate|
      path = File.join(dir, candidate)
      return path if executable_file?(path)
    end
  end
  nil
end

private def executable_file?(path : String) : Bool
  LibC.access(path, 1) == 0 && !File.directory?(path)
end

describe Commander::LuaPluginRuntime do
  it "fails closed when disabled" do
    runtime = Commander::LuaPluginRuntime.new(false)
    request = Commander::PluginRuntimeRequest.new(
      command_id: "example.status",
      plugin_id: "example",
      entrypoint_path: nil,
      context: runtime_snapshot_context
    )

    response = runtime.execute(request)
    response.ok.should be_false
    response.error.should eq("Lua runtime is disabled")
  end

  it "executes a status command through Lua when a Lua binary is available" do
    lua = find_lua_binary
    pending! "Lua executable not available" unless lua

    previous = ENV["COMMANDER_LUA_BIN"]?
    ENV["COMMANDER_LUA_BIN"] = lua.not_nil!
    begin
      with_lua_plugin_file(%(
        commander.command("example.status", function(ctx)
          commander.status("Lua active panel " .. tostring(ctx.active_panel))
        end)
      )) do |path|
        runtime = Commander::LuaPluginRuntime.new(true)
        request = Commander::PluginRuntimeRequest.new(
          command_id: "example.status",
          plugin_id: "example",
          entrypoint_path: path,
          context: runtime_snapshot_context(active_panel: 2)
        )

        response = runtime.execute(request)
        response.ok.should be_true
        response.status_text.should eq("Lua active panel 2")
      end
    ensure
      if previous
        ENV["COMMANDER_LUA_BIN"] = previous
      else
        ENV.delete("COMMANDER_LUA_BIN")
      end
    end
  end

  it "reports unregistered Lua commands" do
    lua = find_lua_binary
    pending! "Lua executable not available" unless lua

    previous = ENV["COMMANDER_LUA_BIN"]?
    ENV["COMMANDER_LUA_BIN"] = lua.not_nil!
    begin
      with_lua_plugin_file(%(
        commander.command("other.status", function(ctx)
          commander.status("wrong")
        end)
      )) do |path|
        runtime = Commander::LuaPluginRuntime.new(true)
        request = Commander::PluginRuntimeRequest.new(
          command_id: "missing.status",
          plugin_id: "example",
          entrypoint_path: path,
          context: runtime_snapshot_context
        )

        response = runtime.execute(request)
        response.ok.should be_false
        response.error.should_not be_nil
        response.error.not_nil!.should contain("Lua command not registered")
      end
    ensure
      if previous
        ENV["COMMANDER_LUA_BIN"] = previous
      else
        ENV.delete("COMMANDER_LUA_BIN")
      end
    end
  end
end

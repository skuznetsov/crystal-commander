require "./renderer"
require "./command_registry"
require "./keymap"
require "./snapshots"
require "./plugin_host"
require "./plugin_runtime"
require "./file_operations"
require "./file_preview"
require "./ui_api"
require "./automation_server"
require "./virtual_fs"

def home_dir : String
  ENV["HOME"]? || "/"
end

KEY_UP = 126
KEY_DOWN = 125
KEY_LEFT = 123
KEY_RIGHT = 124
KEY_HOME = 115
KEY_END = 119
KEY_PAGE_UP = 116
KEY_PAGE_DOWN = 121
KEY_TAB = 48
KEY_BACKSPACE = 51
KEY_ESCAPE = 53
KEY_RETURN = 36
KEY_ENTER = 76
KEY_Q = 12
KEY_SPACE = 49
KEY_F1 = 122
KEY_F2 = 120
KEY_F3 = 99
KEY_F4 = 118
KEY_F5 = 96
KEY_F6 = 97
KEY_F7 = 98
KEY_F8 = 100
KEY_F9 = 101
KEY_F10 = 109

MOD_CONTROL = 1_u32 << 18
MOD_COMMAND = 1_u32 << 20

struct PanelEntry
  getter name : String
  getter size : String
  getter modified : String
  getter path : String
  getter flags : UInt32

  def initialize(@name : String, @size : String, @modified : String, @path : String, @flags : UInt32)
  end

  def directory? : Bool
    (flags & Commander::ROW_FLAG_DIRECTORY) != 0
  end

  def to_snapshot : Commander::EntrySnapshot
    Commander::EntrySnapshot.new(
      name: @name,
      size: @size,
      modified: @modified,
      path: @path,
      flags: @flags,
      uri: Commander::VirtualFS::VirtualPath.parse(@path).to_uri
    )
  end
end

class PanelState
  record ReturnOffset, parent_path : String, child_path : String, cursor : Int32

  getter path : String
  getter entries : Array(PanelEntry)
  getter marked_paths : Set(String)
  property cursor : Int32

  def initialize(start_path : String)
    @path = start_path
    @entries = [] of PanelEntry
    @marked_paths = Set(String).new
    @return_offsets = [] of ReturnOffset
    @cursor = 0
    load_path(start_path)
  end

  def load_path(path : String) : Nil
    provider = Commander::VirtualFS::FileProvider.new
    normalized = File.expand_path(path)
    stat = provider.stat(Commander::VirtualFS::VirtualPath.parse(normalized))
    stat_entry = stat.entries.first?
    normalized = home_dir unless stat.ok && stat_entry && stat_entry.kind == Commander::VirtualFS::EntryKind::Directory

    @path = normalized
    @entries.clear

    parent = File.dirname(@path)
    if parent != @path
      @entries << PanelEntry.new(
        name: "/..",
        size: "UP--DIR",
        modified: Time.local.to_s("%b %-d %H:%M"),
        path: parent,
        flags: Commander::ROW_FLAG_DIRECTORY | Commander::ROW_FLAG_PARENT
      )
    end

    list = provider.list(Commander::VirtualFS::VirtualPath.parse(@path))
    rows = list.entries.map do |entry|
      directory = entry.kind == Commander::VirtualFS::EntryKind::Directory
      permissions = entry.permissions
      executable = false
      executable = (permissions & 0o111_u32) != 0 if permissions && !directory

      flags = 0_u32
      flags |= Commander::ROW_FLAG_DIRECTORY if directory
      flags |= Commander::ROW_FLAG_EXECUTABLE if executable

      display_name = if directory
                       "/#{entry.name}"
                     elsif executable
                       "*#{entry.name}"
                     else
                       entry.name
                     end

      PanelEntry.new(
        name: display_name,
        size: directory ? "<DIR>" : format_size(entry.size || 0_i64),
        modified: entry.modified_at.try(&.to_local.to_s("%b %-d %H:%M")) || "",
        path: entry.path.path,
        flags: flags
      )
    end

    rows.sort_by! { |entry| {entry.directory? ? 0 : 1, entry.name.downcase} }
    @entries.concat(rows)
    clamp_cursor
  end

  def move_cursor(delta : Int32) : Nil
    return if @entries.empty?
    @cursor += delta
    clamp_cursor
  end

  def move_cursor_to(index : Int32) : Nil
    return if @entries.empty?
    @cursor = index
    clamp_cursor
  end

  def selected : PanelEntry?
    return nil if @entries.empty?
    return nil if @cursor < 0 || @cursor >= @entries.size
    @entries[@cursor]
  end

  def enter_directory(path : String) : Bool
    previous_path = @path
    previous_cursor = @cursor
    load_path(path)
    return false if @path == previous_path

    if File.dirname(@path) == previous_path
      remember_return_offset(previous_path, @path, previous_cursor)
    end
    true
  end

  def go_parent : Bool
    child_path = @path
    parent_path = File.dirname(child_path)
    return false if parent_path == child_path

    load_path(parent_path)
    restore_return_offset(parent_path, child_path)
    true
  end

  def toggle_mark_selected : Bool
    selected = selected()
    return false unless selected
    return false if selected.flags & Commander::ROW_FLAG_PARENT != 0

    if @marked_paths.includes?(selected.path)
      @marked_paths.delete(selected.path)
    else
      @marked_paths.add(selected.path)
    end
    true
  end

  def clear_marks : Nil
    @marked_paths.clear
  end

  def display_path : String
    home = home_dir
    if @path.starts_with?(home)
      "~#{@path.byte_slice(home.bytesize, @path.bytesize - home.bytesize)}"
    else
      @path
    end
  end

  def to_render_rows : Array(Commander::Row)
    @entries.map do |entry|
      flags = entry.flags
      flags |= Commander::ROW_FLAG_MARKED if @marked_paths.includes?(entry.path)

      Commander::Row.new(
        name: entry.name,
        size: entry.size,
        modified: entry.modified,
        flags: flags
      )
    end
  end

  def to_snapshot(index : Int32, active : Bool) : Commander::PanelSnapshot
    Commander::PanelSnapshot.new(
      index: index,
      path: @path,
      display_path: display_path,
      cursor: @cursor,
      active: active,
      marked_paths: @marked_paths.to_a,
      entries: @entries.map(&.to_snapshot),
      uri: Commander::VirtualFS::VirtualPath.parse(@path).to_uri
    )
  end

  private def clamp_cursor : Nil
    if @entries.empty?
      @cursor = 0
      return
    end
    @cursor = 0 if @cursor < 0
    max = @entries.size - 1
    @cursor = max.to_i32 if @cursor > max
  end

  private def remember_return_offset(parent_path : String, child_path : String, cursor : Int32) : Nil
    @return_offsets.reject! { |item| item.parent_path == parent_path && item.child_path == child_path }
    @return_offsets << ReturnOffset.new(parent_path, child_path, cursor)
  end

  private def restore_return_offset(parent_path : String, child_path : String) : Nil
    row = @entries.index { |entry| entry.path == child_path }
    if row
      @cursor = row.to_i32
      return
    end

    offset = @return_offsets.reverse_each.find { |item| item.parent_path == parent_path && item.child_path == child_path }
    @cursor = offset.cursor if offset
    clamp_cursor
  end

  private def format_size(bytes : Int64) : String
    units = ["B", "K", "M", "G", "T", "P"]
    value = bytes.to_f64
    unit = 0
    while value >= 1024.0 && unit < units.size - 1
      value /= 1024.0
      unit += 1
    end
    if unit == 0 || value >= 100.0
      "#{value.round.to_i}#{units[unit]}"
    else
      "#{value.round(1)}#{units[unit]}"
    end
  end
end

class CommanderApp
  @panel_count : Int32
  @renderer : Commander::Renderer?
  @commands : Commander::CommandRegistry
  @keymap : Commander::Keymap
  @plugin_host : Commander::PluginHost
  @plugin_runtimes : Hash(String, Commander::PluginRuntime)
  @automation_server : Commander::AutomationServer?
  @panels : Array(PanelState)
  @active_panel : Int32
  @running : Bool
  @status_text : String
  @dry_run : Bool
  @pending_operation : Commander::FileOperationPlan?
  @preview : Commander::PreviewSnapshot?
  @external_view : Commander::ExternalViewSnapshot?

  def initialize
    @panel_count = panel_count_env
    @renderer = nil
    @commands = Commander::CommandRegistry.new
    @keymap = Commander::Keymap.new
    @plugin_host = Commander::PluginHost.new(plugin_root_env)
    @plugin_runtimes = {
      "lua" => Commander::LuaPluginRuntime.new(lua_plugins_enabled?).as(Commander::PluginRuntime),
      "subprocess" => Commander::SubprocessPluginRuntime.new(subprocess_plugins_enabled?).as(Commander::PluginRuntime),
    }
    @automation_server = automation_socket_env.try { |path| Commander::AutomationServer.new(path) }
    @panels = Array(PanelState).new(@panel_count) { PanelState.new(home_dir) }
    @active_panel = 0
    @running = true
    @status_text = "Ready"
    @dry_run = dry_run_requested?
    @pending_operation = nil
    @preview = nil
    @external_view = nil
    @plugin_host.load_manifests
    register_builtin_commands
    register_plugin_manifest_commands
    register_builtin_keys
    register_plugin_manifest_keys
  end

  def run : Nil
    if command_json = automation_command_json_requested
      puts handle_automation_command_json(command_json).to_json
      return
    end

    if headless_command = headless_command_requested
      execute_command(headless_command, headless_command_panel, headless_command_argument)
      puts debug_snapshot.to_json
      return
    end

    if dump_state_requested?
      puts debug_snapshot.to_json
      return
    end

    renderer = Commander::Renderer.new(@panel_count, 1360, 860)
    @renderer = renderer
    unless renderer.show
      raise "renderer window creation failed"
    end

    sync_all
    set_active_panel(0)
    report_plugin_manifest_status
    @automation_server.try(&.start)

    while @running && renderer.pump(16)
      while event = renderer.poll_event
        handle_event(event)
      end
    end
  ensure
    @automation_server.try(&.stop)
    @renderer.try(&.destroy)
  end

  private def panel_count_env : Int32
    value = ENV["PANELS"]?.try(&.to_i?) || 2
    value.clamp(1, 8).to_i32
  end

  private def plugin_root_env : String
    ENV["COMMANDER_PLUGIN_PATH"]? || "plugins"
  end

  private def automation_socket_env : String?
    value = ENV["COMMANDER_AUTOMATION_SOCKET"]?
    return nil unless value
    return nil if value.empty?

    value
  end

  private def subprocess_plugins_enabled? : Bool
    value = ENV["COMMANDER_ENABLE_SUBPROCESS_PLUGINS"]?
    return false unless value

    value == "1" || value.downcase == "true" || value.downcase == "yes"
  end

  private def lua_plugins_enabled? : Bool
    value = ENV["COMMANDER_ENABLE_LUA_PLUGINS"]?
    return false unless value

    value == "1" || value.downcase == "true" || value.downcase == "yes"
  end

  private def dump_state_requested? : Bool
    value = ENV["COMMANDER_DUMP_STATE"]?
    return false unless value

    value == "1" || value.downcase == "true" || value.downcase == "yes"
  end

  private def dry_run_requested? : Bool
    value = ENV["COMMANDER_DRY_RUN"]?
    return false unless value

    value == "1" || value.downcase == "true" || value.downcase == "yes"
  end

  private def headless_command_requested : String?
    ENV["COMMANDER_RUN_COMMAND"]?
  end

  private def automation_command_json_requested : String?
    ENV["COMMANDER_AUTOMATION_COMMAND_JSON"]?
  end

  private def headless_command_panel : Int32
    value = ENV["COMMANDER_COMMAND_PANEL"]?.try(&.to_i?) || @active_panel
    clamp_panel(value.to_i32)
  end

  private def headless_command_argument : String?
    ENV["COMMANDER_COMMAND_ARG"]?
  end

  private def handle_event(event : Commander::Event) : Nil
    case event.type
    when Commander::EventType::Key
      handle_key_event(event)
    when Commander::EventType::Tab
      set_active_panel(@active_panel + 1)
    when Commander::EventType::RowSelected
      panel_index = clamp_panel(event.panel)
      @panels[panel_index].cursor = event.row
      set_active_panel(panel_index)
    when Commander::EventType::RowActivated
      panel_index = clamp_panel(event.panel)
      activate_row(panel_index, event.row)
    when Commander::EventType::MouseDown
      panel_index = clamp_panel(event.panel)
      set_active_panel(panel_index)
      update_status("Mouse panel=#{panel_index + 1} row=#{event.row} x=#{event.x.round(1)} y=#{event.y.round(1)}")
    when Commander::EventType::Quit, Commander::EventType::WindowClose
      @running = false
      renderer_stop
    else
    end
  end

  private def handle_key_event(event : Commander::Event) : Nil
    panel_index = clamp_panel(event.panel)
    set_active_panel(panel_index)

    command_id = @keymap.command_for(event.key_code, event.modifiers)
    execute_command(command_id, panel_index) if command_id
  end

  private def register_builtin_commands : Nil
    @commands.register("panel.cursor_up", "Cursor up", "Move cursor one row up") do |ctx|
      move_cursor(ctx.panel_index, -1)
    end

    @commands.register("panel.cursor_down", "Cursor down", "Move cursor one row down") do |ctx|
      move_cursor(ctx.panel_index, 1)
    end

    @commands.register("panel.cursor_page_up", "Page up", "Move cursor one page up") do |ctx|
      move_cursor(ctx.panel_index, -24)
    end

    @commands.register("panel.cursor_page_down", "Page down", "Move cursor one page down") do |ctx|
      move_cursor(ctx.panel_index, 24)
    end

    @commands.register("panel.cursor_home", "Home", "Move cursor to the first row") do |ctx|
      move_cursor_to(ctx.panel_index, 0)
    end

    @commands.register("panel.cursor_end", "End", "Move cursor to the last row") do |ctx|
      move_cursor_to(ctx.panel_index, @panels[ctx.panel_index].entries.size - 1)
    end

    @commands.register("panel.activate_left", "Activate left panel", "Move focus to the previous panel") do |ctx|
      set_active_panel(ctx.panel_index - 1)
    end

    @commands.register("panel.activate_right", "Activate right panel", "Move focus to the next panel") do |ctx|
      set_active_panel(ctx.panel_index + 1)
    end

    @commands.register("panel.activate_selected", "Activate selected row", "Open directory or report selected file") do |ctx|
      panel = @panels[ctx.panel_index]
      activate_row(ctx.panel_index, panel.cursor)
    end

    @commands.register("panel.go_parent", "Go to parent directory", "Load the parent directory in the current panel") do |ctx|
      go_parent(ctx.panel_index)
    end

    @commands.register("panel.open_path", "Open path", "Load a path in the current panel") do |ctx|
      path = ctx.argument
      if path && !path.empty?
        open_path(ctx.panel_index, path)
      else
        update_status("Open path requires COMMANDER_COMMAND_ARG")
      end
    end

    @commands.register("app.quit", "Quit", "Stop the commander application") do |_ctx|
      @running = false
      renderer_stop
    end

    @commands.register("app.help", "Help", "Show Commander help") do |_ctx|
      update_status("Help is not implemented yet")
    end

    @commands.register("app.menu", "Menu", "Open Commander menu") do |_ctx|
      update_status("Menu is not implemented yet")
    end

    @commands.register("file.view", "View", "View selected file") do |ctx|
      view_selected_file(ctx.panel_index)
    end

    @commands.register("file.view_path", "View path", "Read-only preview of a provided file path") do |ctx|
      path = ctx.argument
      if path && !path.empty?
        view_path(path)
      else
        update_status("View path requires COMMANDER_COMMAND_ARG")
      end
    end

    @commands.register("file.external_view", "External view", "Plan opening the selected file in an external viewer") do |ctx|
      external_view_selected_file(ctx.panel_index)
    end

    @commands.register("file.external_view_path", "External view path", "Plan opening a provided file path in an external viewer") do |ctx|
      path = ctx.argument
      if path && !path.empty?
        external_view_path(path)
      else
        update_status("External view path requires COMMANDER_COMMAND_ARG")
      end
    end

    @commands.register("file.edit", "Edit", "Edit selected file") do |ctx|
      report_file_operation_plan(Commander::FileOperationKind::Edit, ctx.panel_index)
    end

    @commands.register("file.copy", "Copy", "Copy selected entries to another panel") do |ctx|
      report_file_operation_plan(Commander::FileOperationKind::Copy, ctx.panel_index)
    end

    @commands.register("file.copy_to", "Copy to", "Copy selected or marked regular files to a target directory") do |ctx|
      target = ctx.argument
      if target && !target.empty?
        copy_to(ctx.panel_index, target)
      else
        update_status("Copy requires COMMANDER_COMMAND_ARG target directory")
      end
    end

    @commands.register("file.renmov", "RenMov", "Rename or move selected entries") do |ctx|
      report_file_operation_plan(Commander::FileOperationKind::RenameMove, ctx.panel_index)
    end

    @commands.register("file.renmov_to", "RenMov to", "Plan rename/move selected entries to a target directory") do |ctx|
      target = ctx.argument
      if target && !target.empty?
        renmov_to(ctx.panel_index, target)
      else
        update_status("RenMov requires COMMANDER_COMMAND_ARG target directory")
      end
    end

    @commands.register("file.mkdir", "Mkdir", "Create a directory in the active panel") do |ctx|
      report_file_operation_plan(Commander::FileOperationKind::Mkdir, ctx.panel_index)
    end

    @commands.register("file.mkdir_named", "Mkdir named", "Create a directory from command argument") do |ctx|
      name = ctx.argument
      if name && !name.empty?
        mkdir_named(ctx.panel_index, name)
      else
        update_status("Mkdir requires COMMANDER_COMMAND_ARG")
      end
    end

    @commands.register("file.delete", "Delete", "Delete selected entries") do |ctx|
      report_file_operation_plan(Commander::FileOperationKind::Delete, ctx.panel_index)
    end

    @commands.register("file.delete_plan", "Delete plan", "Plan deletion of selected or marked entries") do |ctx|
      delete_plan(ctx.panel_index)
    end

    @commands.register("file.mark_toggle", "Toggle mark", "Mark or unmark the selected entry") do |ctx|
    panel = @panels[ctx.panel_index]
      if panel.toggle_mark_selected
        renderer_set_panel_rows(ctx.panel_index, panel.to_render_rows, panel.cursor)
        update_status("Panel #{ctx.panel_index + 1}: #{panel.marked_paths.size} marked")
      else
        update_status("Nothing to mark")
      end
    end

    @commands.register("file.mark_clear", "Clear marks", "Clear marked entries in the active panel") do |ctx|
      panel = @panels[ctx.panel_index]
      panel.clear_marks
      renderer_set_panel_rows(ctx.panel_index, panel.to_render_rows, panel.cursor)
      update_status("Panel #{ctx.panel_index + 1}: marks cleared")
    end

    @commands.register("file.operation_execute", "Execute pending operation", "Execute the currently pending file operation after confirmation") do |_ctx|
      execute_pending_operation
    end

    @commands.register("file.operation_cancel", "Cancel pending operation", "Clear the currently pending file operation") do |_ctx|
      @pending_operation = nil
      @preview = nil
      update_status("Pending file operation cleared")
    end

    @commands.register("app.pulldown", "PullDn", "Open pull-down menu") do |_ctx|
      update_status("Pull-down menu is not implemented yet")
    end
  end

  private def register_plugin_manifest_commands : Nil
    @plugin_host.register_placeholder_commands(@commands) do |plugin, command|
      manifest = plugin.manifest
      runtime = @plugin_runtimes[manifest.runtime]?
      unless runtime
        update_status("Unsupported plugin runtime: #{manifest.runtime}")
        next
      end

      response = runtime.execute(Commander::PluginRuntimeRequest.new(command.id, manifest.id, plugin.entrypoint_path, debug_snapshot))
      if response.ok
        update_status(response.status_text || "Plugin command executed: #{command.id}")
      else
        update_status(response.error || "Plugin command failed: #{command.id}")
      end
    end
  end

  private def register_builtin_keys : Nil
    @keymap.bind(KEY_UP, "panel.cursor_up")
    @keymap.bind(KEY_DOWN, "panel.cursor_down")
    @keymap.bind(KEY_PAGE_UP, "panel.cursor_page_up")
    @keymap.bind(KEY_PAGE_DOWN, "panel.cursor_page_down")
    @keymap.bind(KEY_HOME, "panel.cursor_home")
    @keymap.bind(KEY_END, "panel.cursor_end")
    @keymap.bind(KEY_LEFT, "panel.activate_left")
    @keymap.bind(KEY_RIGHT, "panel.activate_right")
    @keymap.bind(KEY_RETURN, "panel.activate_selected")
    @keymap.bind(KEY_ENTER, "panel.activate_selected")
    @keymap.bind(KEY_BACKSPACE, "panel.go_parent")
    @keymap.bind(KEY_ESCAPE, "file.operation_cancel")
    @keymap.bind(KEY_RETURN, "file.operation_execute", MOD_CONTROL | MOD_COMMAND)
    @keymap.bind(KEY_ENTER, "file.operation_execute", MOD_CONTROL | MOD_COMMAND)
    @keymap.bind(KEY_SPACE, "file.mark_toggle")
    @keymap.bind(KEY_Q, "app.quit", MOD_CONTROL | MOD_COMMAND)
    @keymap.bind(KEY_F1, "app.help")
    @keymap.bind(KEY_F2, "app.menu")
    @keymap.bind(KEY_F3, "file.view")
    @keymap.bind(KEY_F4, "file.edit")
    @keymap.bind(KEY_F5, "file.copy")
    @keymap.bind(KEY_F6, "file.renmov")
    @keymap.bind(KEY_F7, "file.mkdir")
    @keymap.bind(KEY_F8, "file.delete")
    @keymap.bind(KEY_F9, "app.pulldown")
    @keymap.bind(KEY_F10, "app.quit")
  end

  private def register_plugin_manifest_keys : Nil
    @plugin_host.key_bindings.each do |binding|
      next unless @commands.registered?(binding.command)

      @keymap.bind_spec(binding.key, binding.command)
    end
  end

  private def report_plugin_manifest_status : Nil
    if @plugin_host.load_errors.empty?
      update_status("Loaded #{@plugin_host.manifests.size} plugin manifest(s)")
    else
      update_status("Plugin manifest errors: #{@plugin_host.load_errors.size}")
    end
  end

  private def execute_command(command_id : String, panel_index : Int32, argument : String? = nil) : Nil
    execute_command_bool(command_id, panel_index, argument)
  end

  private def execute_command_bool(command_id : String, panel_index : Int32, argument : String? = nil) : Bool
    context = Commander::CommandContext.new(panel_index, argument)
    return true if @commands.execute(command_id, context)

    update_status("Unknown command: #{command_id}")
    false
  end

  private def move_cursor(panel_index : Int32, delta : Int32) : Nil
    panel = @panels[panel_index]
    panel.move_cursor(delta)
    @renderer.try(&.set_panel_cursor(panel_index, panel.cursor))
    refresh_status_for_active if panel_index == @active_panel
  end

  private def move_cursor_to(panel_index : Int32, index : Int32) : Nil
    panel = @panels[panel_index]
    panel.move_cursor_to(index)
    @renderer.try(&.set_panel_cursor(panel_index, panel.cursor))
    refresh_status_for_active if panel_index == @active_panel
  end

  private def build_file_operation_plan(kind : Commander::FileOperationKind, panel_index : Int32) : Commander::FileOperationPlan
    panel = @panels[panel_index]
    target_panel = @panel_count > 1 ? ((panel_index + 1) % @panel_count).to_i32 : nil
    target_directory = target_panel ? @panels[target_panel].path : nil
    sources = if panel.marked_paths.empty?
                selected = panel.selected
                selected ? [selected.path] : [] of String
              else
                panel.marked_paths.to_a
              end

    Commander::FileOperationPlan.new(
      kind: kind,
      source_panel: panel_index,
      target_panel: target_panel,
      sources: sources,
      target_directory: target_directory
    )
  end

  private def report_file_operation_plan(kind : Commander::FileOperationKind, panel_index : Int32) : Nil
    plan = build_file_operation_plan(kind, panel_index)
    if plan.empty? && kind != Commander::FileOperationKind::Mkdir
      @pending_operation = nil
      update_status("#{kind} pending: no selected entry")
    else
      @pending_operation = plan
      update_status("Plan: #{plan.summary}")
    end
  end

  private def mkdir_named(panel_index : Int32, name : String) : Nil
    base = @panels[panel_index].path
    target = name.starts_with?("/") ? name : File.join(base, name)
    if @dry_run
      @pending_operation = Commander::FileOperationPlan.new(
        kind: Commander::FileOperationKind::Mkdir,
        source_panel: panel_index,
        target_panel: nil,
        sources: [] of String,
        target_directory: target
      )
      update_status("Dry run: mkdir #{target}")
      return
    end

    result = Commander::FileOperations.mkdir(target)
    if result.ok
      @panels[panel_index].load_path(base)
      sync_panel(panel_index)
    end
    update_status("#{result.message}: #{result.path || target}")
  end

  private def copy_to(panel_index : Int32, target_directory : String) : Nil
    plan = build_file_operation_plan(Commander::FileOperationKind::Copy, panel_index)
    if plan.sources.empty?
      update_status("Copy failed: no selected entry")
      return
    end

    if @dry_run
      @pending_operation = Commander::FileOperationPlan.new(
        kind: Commander::FileOperationKind::Copy,
        source_panel: plan.source_panel,
        target_panel: plan.target_panel,
        sources: plan.sources,
        target_directory: target_directory
      )
      update_status("Dry run: #{plan.sources.size} copy item(s) to #{target_directory}")
      return
    end

    results = plan.sources.map do |source|
      Commander::FileOperations.copy_file(source, target_directory)
    end

    ok_count = results.count(&.ok)
    fail_count = results.size - ok_count
    if ok_count > 0
      reload_panel_for_path(target_directory)
    end
    if fail_count == 0
      update_status("Copied #{ok_count} item(s) to #{File.expand_path(target_directory)}")
    else
      first_error = results.find { |result| !result.ok }
      update_status("Copied #{ok_count}, failed #{fail_count}: #{first_error.try(&.message) || "unknown error"}")
    end
  end

  private def renmov_to(panel_index : Int32, target_directory : String) : Nil
    plan = build_file_operation_plan(Commander::FileOperationKind::RenameMove, panel_index)
    if plan.sources.empty?
      update_status("RenMov failed: no selected entry")
      return
    end

    @pending_operation = Commander::FileOperationPlan.new(
      kind: Commander::FileOperationKind::RenameMove,
      source_panel: plan.source_panel,
      target_panel: plan.target_panel,
      sources: plan.sources,
      target_directory: target_directory
    )
    update_status("Plan: RenMov #{plan.sources.size} item(s) to #{target_directory}")
  end

  private def delete_plan(panel_index : Int32) : Nil
    plan = build_file_operation_plan(Commander::FileOperationKind::Delete, panel_index)
    if plan.sources.empty?
      @pending_operation = nil
      update_status("Delete failed: no selected entry")
      return
    end

    @pending_operation = plan
    update_status("Plan: Delete #{plan.sources.size} item(s)")
  end

  private def execute_pending_operation : Nil
    plan = @pending_operation
    unless plan
      update_status("No pending file operation")
      return
    end

    case plan.kind
    when Commander::FileOperationKind::Mkdir
      execute_pending_mkdir(plan)
    when Commander::FileOperationKind::Copy
      execute_pending_copy(plan)
    when Commander::FileOperationKind::RenameMove
      update_status("RenMov execution is not implemented yet: #{plan.summary}")
    when Commander::FileOperationKind::Delete
      update_status("Delete execution is not implemented yet: #{plan.summary}")
    else
      update_status("Execution is not implemented yet: #{plan.summary}")
    end
  end

  private def execute_pending_mkdir(plan : Commander::FileOperationPlan) : Nil
    target = plan.target_directory
    unless target
      update_status("Mkdir execution failed: missing target")
      return
    end

    result = Commander::FileOperations.mkdir(target)
    if result.ok
      reload_panel_for_path(File.dirname(File.expand_path(target)))
      @pending_operation = nil
    end
    update_status("#{result.message}: #{result.path || target}")
  end

  private def execute_pending_copy(plan : Commander::FileOperationPlan) : Nil
    target_directory = plan.target_directory
    unless target_directory
      update_status("Copy execution failed: missing target directory")
      return
    end

    if plan.sources.empty?
      update_status("Copy execution failed: no sources")
      return
    end

    results = plan.sources.map do |source|
      Commander::FileOperations.copy_file(source, target_directory)
    end

    ok_count = results.count(&.ok)
    fail_count = results.size - ok_count
    reload_panel_for_path(target_directory) if ok_count > 0
    @pending_operation = nil if fail_count == 0

    if fail_count == 0
      update_status("Copied #{ok_count} item(s) to #{File.expand_path(target_directory)}")
    else
      first_error = results.find { |result| !result.ok }
      update_status("Copied #{ok_count}, failed #{fail_count}: #{first_error.try(&.message) || "unknown error"}")
    end
  end

  private def reload_panel_for_path(path : String) : Nil
    expanded = File.expand_path(path)
    @panels.each_with_index do |panel, index|
      next unless panel.path == expanded

      panel.load_path(panel.path)
      sync_panel(index.to_i32)
    end
  end

  private def view_selected_file(panel_index : Int32) : Nil
    selected = @panels[panel_index].selected
    unless selected
      @preview = nil
      update_status("View pending: no selected entry")
      return
    end

    view_path(selected.path)
  end

  private def external_view_selected_file(panel_index : Int32) : Nil
    selected = @panels[panel_index].selected
    unless selected
      @external_view = nil
      update_status("External view pending: no selected entry")
      return
    end

    external_view_path(selected.path)
  end

  private def external_view_path(path : String) : Nil
    expanded = File.expand_path(path)
    unless File.file?(expanded)
      @external_view = nil
      update_status("External view failed: not a regular file")
      return
    end

    request = Commander::UI::ExternalViewRequest.new(expanded, readonly: true)
    @external_view = Commander::ExternalViewSnapshot.new(request.path, request.readonly, request.preferred_app)
    update_status("External view planned: #{File.basename(expanded)}")
  end

  private def view_path(path : String) : Nil
    preview = Commander::FilePreview.load(path)
    @preview = preview
    if preview.error
      update_status("View failed: #{preview.error}")
    else
      suffix = preview.truncated ? " (truncated)" : ""
      first_line = preview.content.lines.first? || ""
      update_status("View #{preview.title}#{suffix}: #{first_line}")
    end
  end

  private def go_parent(panel_index : Int32) : Nil
    panel = @panels[panel_index]
    panel.go_parent
    sync_panel(panel_index)
  end

  private def open_path(panel_index : Int32, path : String) : Nil
    panel = @panels[panel_index]
    previous = panel.path
    panel.load_path(path)
    sync_panel(panel_index)
    if panel.path == previous && File.expand_path(path) != previous
      update_status("Open path failed or unavailable: #{path}")
    else
      update_status("Panel #{panel_index + 1}: #{panel.display_path}")
    end
  end

  private def activate_row(panel_index : Int32, row : Int32) : Nil
    panel = @panels[panel_index]
    return if row < 0 || row >= panel.entries.size

    panel.cursor = row
    selected = panel.selected
    return unless selected

    if selected.directory?
      panel.enter_directory(selected.path)
      sync_panel(panel_index)
    else
      update_status("Selected file: #{selected.path}")
      sync_panel(panel_index)
    end
  end

  private def set_active_panel(index : Int32) : Nil
    if @panel_count <= 0
      @active_panel = 0
      return
    end

    wrapped = index
    wrapped = @panel_count - 1 if wrapped < 0
    wrapped = 0 if wrapped >= @panel_count
    @active_panel = wrapped
    @renderer.try(&.set_active_panel(@active_panel))
    refresh_status_for_active
  end

  private def sync_all : Nil
    @panel_count.times do |idx|
      sync_panel(idx.to_i32)
    end
    refresh_status_for_active
  end

  private def sync_panel(panel_index : Int32) : Nil
    panel = @panels[panel_index]
    @renderer.try(&.set_panel_path(panel_index, panel.display_path))
    renderer_set_panel_rows(panel_index, panel.to_render_rows, panel.cursor)
    refresh_status_for_active if panel_index == @active_panel
  end

  private def refresh_status_for_active : Nil
    panel = @panels[@active_panel]
    selected = panel.selected
    if selected
      update_status("Panel #{@active_panel + 1}: #{selected.name}  #{selected.size}  #{selected.modified}")
    else
      update_status("Panel #{@active_panel + 1}: empty")
    end
  end

  private def update_status(text : String) : Nil
    @status_text = text
    @renderer.try(&.set_status_text(text))
  end

  private def renderer_stop : Nil
    @renderer.try(&.stop)
  end

  private def renderer_set_panel_rows(panel_index : Int32, rows : Array(Commander::Row), cursor : Int32) : Nil
    @renderer.try(&.set_panel_rows(panel_index, rows, cursor))
  end

  private def debug_snapshot : Commander::AppSnapshot
    panels = @panels.map_with_index do |panel, index|
      panel.to_snapshot(index.to_i32, index == @active_panel)
    end

    Commander::AppSnapshot.new(
      active_panel: @active_panel,
      panel_count: @panel_count,
      running: @running,
      status_text: @status_text,
      dry_run: @dry_run,
      plugin_root: @plugin_host.root,
      plugins: @plugin_host.to_snapshots,
      plugin_runtimes: plugin_runtime_snapshots,
      plugin_errors: @plugin_host.load_errors,
      commands: @commands.to_snapshots,
      pending_operation: @pending_operation.try(&.to_snapshot),
      preview: @preview,
      external_view: @external_view,
      panels: panels
    )
  end

  private def handle_automation_command(command : Commander::AutomationCommand) : Commander::AutomationResponse
    previous_dry_run = @dry_run
    @dry_run = command.dry_run
    ok = execute_command_bool(command.command_id, clamp_panel(command.panel_index), command.argument)
    Commander::AutomationResponse.new(ok, @status_text, debug_snapshot, ok ? nil : @status_text)
  ensure
    @dry_run = previous_dry_run == true
  end

  private def handle_automation_command_json(command_json : String) : Commander::AutomationResponse
    command = Commander::AutomationCommand.from_json(command_json)
    handle_automation_command(command)
  rescue ex : JSON::ParseException | JSON::SerializableError
    @status_text = "Automation JSON command failed"
    Commander::AutomationResponse.new(false, @status_text, debug_snapshot, ex.message)
  end

  private def plugin_runtime_snapshots : Array(Commander::PluginRuntimeSnapshot)
    @plugin_runtimes.values
      .sort_by(&.runtime_name)
      .map { |runtime| Commander::PluginRuntimeSnapshot.new(runtime.runtime_name, runtime.enabled?) }
  end

  private def clamp_panel(index : Int32) : Int32
    return @active_panel if index < 0
    return @active_panel if index >= @panel_count
    index
  end
end

CommanderApp.new.run

require "./renderer"
require "./command_registry"
require "./keymap"
require "./snapshots"
require "./plugin_host"
require "./plugin_runtime"
require "./file_operations"
require "./file_preview"
require "./panel_state"
require "./ui_api"
require "./automation_server"
require "./virtual_fs"


class WorkspaceTabState
  property title : String
  property panels : Array(PanelState)
  property active_panel : Int32

  def initialize(@title : String, @panels : Array(PanelState), @active_panel : Int32 = 0)
  end

  def to_snapshot(index : Int32, active : Bool) : Commander::TabSnapshot
    Commander::TabSnapshot.new(
      index: index,
      title: @title,
      active: active,
      panel_count: @panels.size,
      active_panel: @active_panel,
      panel_uris: @panels.map(&.location.to_uri)
    )
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
  @tabs : Array(WorkspaceTabState)
  @active_tab : Int32
  @panels : Array(PanelState)
  @active_panel : Int32
  @running : Bool
  @status_text : String
  @dry_run : Bool
  @pending_operation : Commander::FileOperationPlan?
  @preview : Commander::PreviewSnapshot?
  @external_view : Commander::ExternalViewSnapshot?
  @viewer_sessions : Array(Commander::ViewerSessionSnapshot)
  @next_viewer_session_id : Int32
  @plugin_actions : Array(Commander::PluginActionSnapshot)

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
    @tabs = [WorkspaceTabState.new("Tab 1", @panels, 0)]
    @active_tab = 0
    @active_panel = 0
    @running = true
    @status_text = "Ready"
    @dry_run = dry_run_requested?
    @pending_operation = nil
    @preview = nil
    @external_view = nil
    @viewer_sessions = [] of Commander::ViewerSessionSnapshot
    @next_viewer_session_id = 0
    @plugin_actions = [] of Commander::PluginActionSnapshot
    @plugin_host.load_manifests
    register_builtin_commands
    register_plugin_manifest_commands
    register_builtin_keys
    register_plugin_manifest_keys
  end

  def run : Nil
    if commands_json = automation_commands_json_requested
      puts handle_automation_commands_json(commands_json).to_json
      return
    end

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

    sync_tabs
    sync_all
    set_active_panel(0)
    report_plugin_manifest_status
    @automation_server.try do |server|
      server.start(
        -> { debug_snapshot },
        ->(command : Commander::AutomationCommand) { Commander::AutomationPolicy.ipc_allowed?(command, @commands) }
      ) { |command| handle_automation_command(command) }
    end

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

  private def automation_commands_json_requested : String?
    ENV["COMMANDER_AUTOMATION_COMMANDS_JSON"]?
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

    @commands.register("tab.new", "New tab", "Create a new workspace tab") do |_ctx|
      new_tab
    end

    @commands.register("tab.next", "Next tab", "Activate the next workspace tab") do |_ctx|
      switch_tab(@active_tab + 1)
    end

    @commands.register("tab.previous", "Previous tab", "Activate the previous workspace tab") do |_ctx|
      switch_tab(@active_tab - 1)
    end

    @commands.register("tab.close", "Close tab", "Close the active workspace tab") do |_ctx|
      close_active_tab
    end

    @commands.register("tab.rename", "Rename tab", "Rename the active workspace tab") do |ctx|
      title = ctx.argument
      if title && !title.empty?
        rename_active_tab(title)
      else
        update_status("Tab rename requires COMMANDER_COMMAND_ARG")
      end
    end

    @commands.register("tab.set_panel_count", "Set tab panel count", "Set the panel count for the active workspace tab") do |ctx|
      count = ctx.argument.try(&.to_i?)
      if count
        set_active_tab_panel_count(count)
      else
        update_status("Tab panel count requires integer COMMANDER_COMMAND_ARG")
      end
    end

    @commands.register("vfs.probe_uri", "Probe VFS URI", "Probe a URI through the VirtualFS registry without changing panels") do |ctx|
      uri = ctx.argument
      if uri && !uri.empty?
        probe_vfs_uri(uri)
      else
        update_status("VFS probe requires COMMANDER_COMMAND_ARG")
      end
    end

    @commands.register("vfs.execute_pending_action", "Execute pending VFS action", "Execute the first pending read-only plugin VFS action") do |_ctx|
      execute_pending_vfs_action
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
        view_path(path, ctx.panel_index)
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

    @commands.register("viewer.close", "Close viewer", "Close the active viewer session") do |_ctx|
      close_active_viewer
    end

    @commands.register("viewer.scroll", "Scroll viewer", "Scroll the active viewer by line count from command argument") do |ctx|
      scroll_active_viewer(ctx.argument)
    end

    @commands.register("viewer.search", "Search viewer", "Search within the active viewer from command argument") do |ctx|
      search_active_viewer(ctx.argument)
    end

    @commands.register("file.copy", "Copy", "Copy selected entries to another panel", mutating: true) do |ctx|
      report_file_operation_plan(Commander::FileOperationKind::Copy, ctx.panel_index)
    end

    @commands.register("file.copy_to", "Copy to", "Copy selected or marked regular files to a target directory", mutating: true) do |ctx|
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

    @commands.register("file.mkdir", "Mkdir", "Create a directory in the active panel", mutating: true) do |ctx|
      report_file_operation_plan(Commander::FileOperationKind::Mkdir, ctx.panel_index)
    end

    @commands.register("file.mkdir_named", "Mkdir named", "Create a directory from command argument", mutating: true) do |ctx|
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

    @commands.register("file.operation_execute", "Execute pending operation", "Execute the currently pending file operation after confirmation", mutating: true) do |_ctx|
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
        capture_plugin_actions(manifest.id, command.id, response.actions)
        action_suffix = response.actions.empty? ? "" : " (#{response.actions.size} action(s) pending)"
        update_status("#{response.status_text || "Plugin command executed: #{command.id}"}#{action_suffix}")
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

  private def new_tab : Nil
    save_active_tab_state
    panels = Array(PanelState).new(@panel_count) { PanelState.new(home_dir) }
    @tabs << WorkspaceTabState.new("Tab #{@tabs.size + 1}", panels, 0)
    @active_tab = @tabs.size - 1
    @panels = panels
    @active_panel = 0
    @panel_count = @panels.size
    sync_all
    sync_tabs
    set_active_panel(0)
    update_status("Tab #{@active_tab + 1}: #{@tabs[@active_tab].title}")
  end

  private def switch_tab(index : Int32) : Nil
    return if @tabs.empty?

    save_active_tab_state
    wrapped = index
    wrapped = @tabs.size - 1 if wrapped < 0
    wrapped = 0 if wrapped >= @tabs.size
    @active_tab = wrapped
    restore_active_tab_state
    sync_all
    sync_tabs
    set_active_panel(@active_panel)
    update_status("Tab #{@active_tab + 1}: #{@tabs[@active_tab].title}")
  end

  private def close_active_tab : Nil
    if @tabs.size <= 1
      update_status("Cannot close the last tab")
      return
    end

    @tabs.delete_at(@active_tab)
    @active_tab = @tabs.size - 1 if @active_tab >= @tabs.size
    restore_active_tab_state
    sync_all
    sync_tabs
    set_active_panel(@active_panel)
    update_status("Closed tab; active tab #{@active_tab + 1}")
  end

  private def rename_active_tab(title : String) : Nil
    clean_title = title.strip
    if clean_title.empty?
      update_status("Tab rename requires a non-empty title")
      return
    end

    @tabs[@active_tab].title = clean_title
    sync_tabs
    update_status("Tab #{@active_tab + 1} renamed: #{clean_title}")
  end

  private def set_active_tab_panel_count(count : Int32) : Nil
    new_count = count.clamp(1, 8).to_i32
    save_active_tab_state

    if new_count > @panels.size
      (new_count - @panels.size).times do
        @panels << PanelState.new(home_dir)
      end
    elsif new_count < @panels.size
      @panels = @panels.first(new_count)
    end

    @panel_count = @panels.size
    @active_panel = 0 if @active_panel >= @panel_count
    @tabs[@active_tab].panels = @panels
    @tabs[@active_tab].active_panel = @active_panel
    sync_all
    sync_tabs
    set_active_panel(@active_panel)
    update_status("Tab #{@active_tab + 1} panel count: #{@panel_count}")
  end

  private def save_active_tab_state : Nil
    return if @tabs.empty?

    tab = @tabs[@active_tab]
    tab.panels = @panels
    tab.active_panel = @active_panel
  end

  private def restore_active_tab_state : Nil
    tab = @tabs[@active_tab]
    @panels = tab.panels
    @active_panel = tab.active_panel
    @panel_count = @panels.size
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

    view_path(selected.path, panel_index)
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

  private def view_path(path : String, panel_index : Int32? = nil) : Nil
    preview = Commander::FilePreview.load(path)
    @preview = preview
    if preview.error
      update_status("View failed: #{preview.error}")
    else
      open_viewer_session(preview, panel_index)
      suffix = preview.truncated ? " (truncated)" : ""
      first_line = preview.content.lines.first? || ""
      update_status("View #{preview.title}#{suffix}: #{first_line}")
    end
  end

  private def open_viewer_session(preview : Commander::PreviewSnapshot, panel_index : Int32?) : Nil
    @next_viewer_session_id += 1
    @viewer_sessions << Commander::ViewerSessionSnapshot.new(
      id: "viewer-#{@next_viewer_session_id}",
      panel_index: panel_index,
      path: preview.path,
      title: preview.title,
      mode: "text",
      scroll_offset: 0,
      cursor_line: 0,
      cursor_col: 0,
      search_term: nil,
      dirty: false,
      readonly: true,
      truncated: preview.truncated,
      error: preview.error
    )
  end

  private def close_active_viewer : Nil
    session = @viewer_sessions.pop?
    if session
      update_status("Closed viewer: #{session.title}")
    else
      update_status("No active viewer")
    end
  end

  private def scroll_active_viewer(argument : String?) : Nil
    index = @viewer_sessions.size - 1
    if index < 0
      update_status("No active viewer")
      return
    end

    delta = argument.try(&.to_i?) || 0
    session = @viewer_sessions[index]
    @viewer_sessions[index] = session.with_scroll_offset(session.scroll_offset + delta)
    update_status("Viewer #{session.title}: scroll #{@viewer_sessions[index].scroll_offset}")
  end

  private def search_active_viewer(term : String?) : Nil
    index = @viewer_sessions.size - 1
    if index < 0
      update_status("No active viewer")
      return
    end

    search = term || ""
    if search.empty?
      update_status("Viewer search requires COMMANDER_COMMAND_ARG")
      return
    end

    session = @viewer_sessions[index]
    preview = Commander::FilePreview.load(session.path)
    if preview.error
      update_status("Viewer search failed: #{preview.error}")
      return
    end

    line_index = preview.content.lines.index { |line| line.includes?(search) }
    unless line_index
      @viewer_sessions[index] = session.with_search(search, session.cursor_line, session.cursor_col)
      update_status("Viewer search not found: #{search}")
      return
    end

    line = preview.content.lines[line_index]
    col = line.index(search).try(&.to_i32) || 0
    @viewer_sessions[index] = session.with_search(search, line_index.to_i32, col)
    update_status("Viewer search #{search}: line #{line_index + 1}")
  end

  private def go_parent(panel_index : Int32) : Nil
    panel = @panels[panel_index]
    panel.go_parent
    sync_panel(panel_index)
  end

  private def open_path(panel_index : Int32, path : String) : Nil
    if path.includes?("://")
      open_uri(panel_index, path)
      return
    end

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

  private def open_uri(panel_index : Int32, uri : String) : Nil
    path = Commander::VirtualFS::VirtualPath.parse(uri)
    if path.scheme == "file"
      open_path(panel_index, path.path)
      return
    end

    response = Commander::VirtualFS::Registry.default.dispatch(
      Commander::VirtualFS::Request.new(Commander::VirtualFS::Operation::List, path)
    )
    if response.ok
      update_status("Remote panel loading is not wired yet: #{path.to_uri}")
    else
      error = response.error
      update_status("Open URI failed: #{error.try(&.message) || "unknown VFS error"}")
    end
  rescue ex : Commander::VirtualFS::VfsException
    update_status("Open URI failed: #{ex.vfs_error.message}")
  rescue ex : ArgumentError
    update_status("Open URI failed: #{ex.message || ex.class.name}")
  end

  private def probe_vfs_uri(uri : String) : Nil
    path = Commander::VirtualFS::VirtualPath.parse(uri)
    operation = path.local? ? Commander::VirtualFS::Operation::Stat : Commander::VirtualFS::Operation::List
    response = Commander::VirtualFS::Registry.default.dispatch(
      Commander::VirtualFS::Request.new(operation, path)
    )

    if response.ok
      suffix = operation == Commander::VirtualFS::Operation::List ? "#{response.entries.size} entries" : "ok"
      update_status("VFS probe #{path.to_uri}: #{suffix}")
    else
      error = response.error
      update_status("VFS probe failed: #{error.try(&.message) || "unknown VFS error"}")
    end
  rescue ex : Commander::VirtualFS::VfsException
    update_status("VFS probe failed: #{ex.vfs_error.message}")
  rescue ex : ArgumentError
    update_status("VFS probe failed: #{ex.message || ex.class.name}")
  end

  private def execute_pending_vfs_action : Nil
    action = @plugin_actions.first?
    unless action
      update_status("No pending plugin VFS action")
      return
    end

    unless action.kind == "vfs"
      update_status("Unsupported plugin action kind: #{action.kind}")
      return
    end

    operation = read_only_vfs_operation(action.operation)
    unless operation
      update_status("Plugin VFS action requires policy: #{action.operation}")
      return
    end

    path = Commander::VirtualFS::VirtualPath.parse(action.uri)
    response = Commander::VirtualFS::Registry.default.dispatch(
      Commander::VirtualFS::Request.new(operation, path)
    )

    if response.ok
      suffix = operation == Commander::VirtualFS::Operation::List ? "#{response.entries.size} entries" : "ok"
      update_status("Plugin VFS action #{action.operation} #{path.to_uri}: #{suffix}")
    else
      error = response.error
      update_status("Plugin VFS action failed: #{error.try(&.message) || "unknown VFS error"}")
    end
  rescue ex : Commander::VirtualFS::VfsException
    update_status("Plugin VFS action failed: #{ex.vfs_error.message}")
  rescue ex : ArgumentError
    update_status("Plugin VFS action failed: #{ex.message || ex.class.name}")
  end

  private def read_only_vfs_operation(value : String) : Commander::VirtualFS::Operation?
    case value
    when "stat"
      Commander::VirtualFS::Operation::Stat
    when "list"
      Commander::VirtualFS::Operation::List
    else
      nil
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
    @tabs[@active_tab].active_panel = @active_panel unless @tabs.empty?
    @renderer.try(&.set_active_panel(@active_panel))
    refresh_status_for_active
  end

  private def sync_all : Nil
    @panel_count.times do |idx|
      sync_panel(idx.to_i32)
    end
    refresh_status_for_active
  end

  private def sync_tabs : Nil
    @renderer.try(&.set_tab_bar(@tabs.map_with_index { |tab, index| {tab.title, index == @active_tab, tab.panels.size} }))
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
    save_active_tab_state
    panels = @panels.map_with_index do |panel, index|
      panel.to_snapshot(index.to_i32, index == @active_panel)
    end
    tabs = @tabs.map_with_index do |tab, index|
      tab.to_snapshot(index.to_i32, index == @active_tab)
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
      viewer_sessions: @viewer_sessions,
      panels: panels,
      plugin_actions: @plugin_actions,
      active_tab: @active_tab,
      tabs: tabs
    )
  end

  private def capture_plugin_actions(plugin_id : String, command_id : String, actions : Array(Commander::PluginRuntimeAction)) : Nil
    @plugin_actions = actions.map do |action|
      Commander::PluginActionSnapshot.new(
        plugin_id: plugin_id,
        command_id: command_id,
        kind: action.kind,
        operation: action.operation,
        uri: action.uri,
        target_uri: action.target_uri
      )
    end
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

  private def handle_automation_commands_json(commands_json : String) : Commander::AutomationResponse
    commands = Array(Commander::AutomationCommand).from_json(commands_json)
    ok = true
    commands.each do |command|
      response = handle_automation_command(command)
      ok = false unless response.ok
      break unless response.ok
    end
    Commander::AutomationResponse.new(ok, @status_text, debug_snapshot, ok ? nil : @status_text)
  rescue ex : JSON::ParseException | JSON::SerializableError
    @status_text = "Automation JSON command list failed"
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

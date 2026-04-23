require "json"

module Commander
  struct CommandSnapshot
    include JSON::Serializable

    getter id : String
    getter title : String
    getter description : String
    getter plugin_id : String?
    getter mutating : Bool

    def initialize(@id : String, @title : String, @description : String, @plugin_id : String?, @mutating : Bool = false)
    end
  end

  struct EntrySnapshot
    include JSON::Serializable

    getter name : String
    getter size : String
    getter modified : String
    getter path : String
    getter uri : String
    getter flags : UInt32

    def initialize(@name : String, @size : String, @modified : String, @path : String, @flags : UInt32, uri : String? = nil)
      @uri = uri || "file://#{@path}"
    end
  end

  struct PanelSnapshot
    include JSON::Serializable

    getter index : Int32
    getter path : String
    getter uri : String
    getter display_path : String
    getter cursor : Int32
    getter active : Bool
    getter marked_paths : Array(String)
    getter entries : Array(EntrySnapshot)

    def initialize(
      @index : Int32,
      @path : String,
      @display_path : String,
      @cursor : Int32,
      @active : Bool,
      @marked_paths : Array(String),
      @entries : Array(EntrySnapshot),
      uri : String? = nil
    )
      @uri = uri || "file://#{@path}"
    end
  end

  struct OperationPlanSnapshot
    include JSON::Serializable

    getter kind : String
    getter source_panel : Int32
    getter target_panel : Int32?
    getter sources : Array(String)
    getter target_directory : String?
    getter summary : String

    def initialize(
      @kind : String,
      @source_panel : Int32,
      @target_panel : Int32?,
      @sources : Array(String),
      @target_directory : String?,
      @summary : String
    )
    end
  end

  struct PreviewSnapshot
    include JSON::Serializable

    getter path : String
    getter title : String
    getter content : String
    getter truncated : Bool
    getter error : String?

    def initialize(@path : String, @title : String, @content : String, @truncated : Bool, @error : String?)
    end
  end

  struct ExternalViewSnapshot
    include JSON::Serializable

    getter path : String
    getter readonly : Bool
    getter preferred_app : String?

    def initialize(@path : String, @readonly : Bool = true, @preferred_app : String? = nil)
    end
  end

  struct ViewerSessionSnapshot
    include JSON::Serializable

    getter id : String
    getter panel_index : Int32?
    getter path : String
    getter title : String
    getter mode : String
    getter scroll_offset : Int32
    getter cursor_line : Int32
    getter cursor_col : Int32
    getter search_term : String?
    getter dirty : Bool
    getter readonly : Bool
    getter truncated : Bool
    getter error : String?

    def initialize(
      @id : String,
      @panel_index : Int32?,
      @path : String,
      @title : String,
      @mode : String = "text",
      @scroll_offset : Int32 = 0,
      @cursor_line : Int32 = 0,
      @cursor_col : Int32 = 0,
      @search_term : String? = nil,
      @dirty : Bool = false,
      @readonly : Bool = true,
      @truncated : Bool = false,
      @error : String? = nil
    )
    end

    def with_scroll_offset(value : Int32) : ViewerSessionSnapshot
      ViewerSessionSnapshot.new(
        id: @id,
        panel_index: @panel_index,
        path: @path,
        title: @title,
        mode: @mode,
        scroll_offset: value < 0 ? 0 : value,
        cursor_line: @cursor_line,
        cursor_col: @cursor_col,
        search_term: @search_term,
        dirty: @dirty,
        readonly: @readonly,
        truncated: @truncated,
        error: @error
      )
    end

    def with_search(term : String?, line : Int32, col : Int32 = 0) : ViewerSessionSnapshot
      ViewerSessionSnapshot.new(
        id: @id,
        panel_index: @panel_index,
        path: @path,
        title: @title,
        mode: @mode,
        scroll_offset: @scroll_offset,
        cursor_line: line < 0 ? 0 : line,
        cursor_col: col < 0 ? 0 : col,
        search_term: term,
        dirty: @dirty,
        readonly: @readonly,
        truncated: @truncated,
        error: @error
      )
    end
  end

  struct ViewerConfigSnapshot
    include JSON::Serializable

    getter external_viewer : String?
    getter external_editor : String?
    getter max_buffer_size : Int64
    getter tab_width : Int32
    getter show_line_numbers : Bool
    getter word_wrap : Bool

    def initialize(
      @external_viewer : String? = nil,
      @external_editor : String? = nil,
      @max_buffer_size : Int64 = 32768_i64,
      @tab_width : Int32 = 4,
      @show_line_numbers : Bool = false,
      @word_wrap : Bool = false
    )
    end
  end

  struct PluginSnapshot
    include JSON::Serializable

    getter id : String
    getter name : String
    getter version : String
    getter api_version : String
    getter runtime : String
    getter entrypoint : String?
    getter entrypoint_path : String?
    getter permissions : Array(String)
    getter command_ids : Array(String)
    getter key_bindings : Array(String)

    def initialize(
      @id : String,
      @name : String,
      @version : String,
      @api_version : String,
      @runtime : String,
      @entrypoint : String?,
      @entrypoint_path : String?,
      @permissions : Array(String),
      @command_ids : Array(String),
      @key_bindings : Array(String)
    )
    end
  end

  struct PluginRuntimeSnapshot
    include JSON::Serializable

    getter name : String
    getter enabled : Bool

    def initialize(@name : String, @enabled : Bool)
    end
  end

  struct PluginActionSnapshot
    include JSON::Serializable

    getter plugin_id : String
    getter command_id : String
    getter kind : String
    getter operation : String
    getter uri : String
    getter target_uri : String?

    def initialize(@plugin_id : String, @command_id : String, @kind : String, @operation : String, @uri : String, @target_uri : String? = nil)
    end
  end

  struct TabSnapshot
    include JSON::Serializable

    getter index : Int32
    getter title : String
    getter active : Bool
    getter panel_count : Int32
    getter active_panel : Int32
    getter panel_uris : Array(String)

    def initialize(@index : Int32, @title : String, @active : Bool, @panel_count : Int32, @active_panel : Int32, @panel_uris : Array(String))
    end
  end

  struct AppSnapshot
    include JSON::Serializable

    getter active_panel : Int32
    getter panel_count : Int32
    getter running : Bool
    getter status_text : String
    getter dry_run : Bool
    getter plugin_root : String
    getter plugins : Array(PluginSnapshot)
    getter plugin_runtimes : Array(PluginRuntimeSnapshot)
    getter plugin_errors : Array(String)
    getter plugin_actions : Array(PluginActionSnapshot)
    getter commands : Array(CommandSnapshot)
    getter pending_operation : OperationPlanSnapshot?
    getter preview : PreviewSnapshot?
    getter external_view : ExternalViewSnapshot?
    getter viewer_config : ViewerConfigSnapshot
    getter viewer_sessions : Array(ViewerSessionSnapshot)
    getter panels : Array(PanelSnapshot)
    getter active_tab : Int32
    getter tabs : Array(TabSnapshot)

    def initialize(
      @active_panel : Int32,
      @panel_count : Int32,
      @running : Bool,
      @status_text : String,
      @dry_run : Bool,
      @plugin_root : String,
      @plugins : Array(PluginSnapshot),
      @plugin_runtimes : Array(PluginRuntimeSnapshot),
      @plugin_errors : Array(String),
      @commands : Array(CommandSnapshot),
      @pending_operation : OperationPlanSnapshot?,
      @preview : PreviewSnapshot?,
      @external_view : ExternalViewSnapshot?,
      @panels : Array(PanelSnapshot),
      @viewer_config : ViewerConfigSnapshot = ViewerConfigSnapshot.new,
      @viewer_sessions : Array(ViewerSessionSnapshot) = [] of ViewerSessionSnapshot,
      @plugin_actions : Array(PluginActionSnapshot) = [] of PluginActionSnapshot,
      @active_tab : Int32 = 0,
      @tabs : Array(TabSnapshot) = [] of TabSnapshot
    )
    end
  end
end

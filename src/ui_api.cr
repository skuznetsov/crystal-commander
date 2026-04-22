require "./snapshots"

module Commander
  module UI
    enum EventKind
      Key
      MouseDown
      MouseUp
      Scroll
      Resize
      Focus
    end

    enum DrawKind
      FillRect
      StrokeRect
      Text
      Line
      Clip
    end

    struct Rect
      getter x : Int32
      getter y : Int32
      getter width : Int32
      getter height : Int32

      def initialize(@x : Int32, @y : Int32, @width : Int32, @height : Int32)
      end
    end

    struct UIEvent
      getter kind : EventKind
      getter key_code : Int32?
      getter modifiers : UInt32
      getter x : Float64?
      getter y : Float64?
      getter delta_x : Float64?
      getter delta_y : Float64?

      def initialize(
        @kind : EventKind,
        @key_code : Int32? = nil,
        @modifiers : UInt32 = 0_u32,
        @x : Float64? = nil,
        @y : Float64? = nil,
        @delta_x : Float64? = nil,
        @delta_y : Float64? = nil
      )
      end
    end

    struct DrawCommand
      getter kind : DrawKind
      getter rect : Rect?
      getter text : String?
      getter color : String?
      getter style : String?

      def initialize(@kind : DrawKind, @rect : Rect? = nil, @text : String? = nil, @color : String? = nil, @style : String? = nil)
      end
    end

    struct Theme
      getter background : String
      getter foreground : String
      getter accent : String
      getter selection : String
      getter header : String

      def initialize(
        @background : String = "mc-blue",
        @foreground : String = "white",
        @accent : String = "cyan",
        @selection : String = "cyan",
        @header : String = "dark-gray"
      )
      end
    end

    struct TextBuffer
      getter title : String
      getter content : String
      getter cursor : Int32
      getter scroll_offset : Int32
      getter readonly : Bool

      def initialize(@title : String, @content : String, @cursor : Int32 = 0, @scroll_offset : Int32 = 0, @readonly : Bool = true)
      end
    end

    struct ExternalViewRequest
      getter path : String
      getter readonly : Bool
      getter preferred_app : String?

      def initialize(@path : String, @readonly : Bool = true, @preferred_app : String? = nil)
      end

      def self.from_snapshot(snapshot : ExternalViewSnapshot) : ExternalViewRequest
        new(snapshot.path, snapshot.readonly, snapshot.preferred_app)
      end
    end

    struct FilePanelView
      getter index : Int32
      getter path : String
      getter title : String
      getter cursor : Int32
      getter active : Bool
      getter entries : Array(EntrySnapshot)
      getter marked_paths : Array(String)

      def initialize(snapshot : PanelSnapshot)
        @index = snapshot.index
        @path = snapshot.path
        @title = snapshot.display_path
        @cursor = snapshot.cursor
        @active = snapshot.active
        @entries = snapshot.entries
        @marked_paths = snapshot.marked_paths
      end

      def selected_entry : EntrySnapshot?
        return nil if @cursor < 0 || @cursor >= @entries.size

        @entries[@cursor]
      end
    end

    struct WorkspaceView
      getter active_tab : Int32
      getter active_panel : Int32
      getter status_text : String
      getter panels : Array(FilePanelView)
      getter command_ids : Array(String)
      getter external_view : ExternalViewRequest?

      def initialize(snapshot : AppSnapshot)
        @active_tab = snapshot.active_tab
        @active_panel = snapshot.active_panel
        @status_text = snapshot.status_text
        @panels = snapshot.panels.map { |panel| FilePanelView.new(panel) }
        @command_ids = snapshot.commands.map(&.id)
        @external_view = snapshot.external_view.try { |view| ExternalViewRequest.from_snapshot(view) }
      end
    end

    def self.workspace(snapshot : AppSnapshot) : WorkspaceView
      WorkspaceView.new(snapshot)
    end
  end
end

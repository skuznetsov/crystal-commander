require "./snapshots"

module Commander
  module UI
    enum EventKind
      Key
      MouseDown
      MouseUp
      MouseMove
      Scroll
      Resize
      Focus
      Wakeup
    end

    enum DrawKind
      FillRect
      StrokeRect
      Text
      Line
      Clip
      Image
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
      getter metadata : Hash(String, String)

      def initialize(
        @kind : DrawKind,
        @rect : Rect? = nil,
        @text : String? = nil,
        @color : String? = nil,
        @style : String? = nil,
        @metadata : Hash(String, String) = {} of String => String
      )
      end

      def self.fill_rect(rect : Rect, color : String, style : String? = nil) : DrawCommand
        new(DrawKind::FillRect, rect: rect, color: color, style: style)
      end

      def self.stroke_rect(rect : Rect, color : String, style : String? = nil) : DrawCommand
        new(DrawKind::StrokeRect, rect: rect, color: color, style: style)
      end

      def self.text(rect : Rect, value : String, color : String, style : String? = nil) : DrawCommand
        new(DrawKind::Text, rect: rect, text: value, color: color, style: style)
      end

      def self.clip(rect : Rect) : DrawCommand
        new(DrawKind::Clip, rect: rect)
      end
    end

    struct Theme
      getter background : String
      getter foreground : String
      getter accent : String
      getter selection : String
      getter header : String
      getter border : String
      getter status : String

      def initialize(
        @background : String = "mc-blue",
        @foreground : String = "white",
        @accent : String = "cyan",
        @selection : String = "cyan",
        @header : String = "dark-gray",
        @border : String = "cyan",
        @status : String = "black"
      )
      end
    end

    struct DrawFrame
      getter bounds : Rect
      getter theme : Theme
      getter commands : Array(DrawCommand)

      def initialize(@bounds : Rect, @theme : Theme, @commands : Array(DrawCommand))
      end
    end

    abstract class Backend
      getter name : String
      getter theme : Theme

      def initialize(@name : String, @theme : Theme = Theme.new)
      end

      abstract def draw(commands : Array(DrawCommand)) : Nil

      def draw(frame : DrawFrame) : Nil
        draw(frame.commands)
      end

      abstract def poll_event : UIEvent?
    end

    class RecordingBackend < Backend
      getter frames : Array(Array(DrawCommand))

      def initialize(name : String = "recording", theme : Theme = Theme.new, events : Array(UIEvent) = [] of UIEvent)
        super(name, theme)
        @events = events
        @frames = [] of Array(DrawCommand)
      end

      def draw(commands : Array(DrawCommand)) : Nil
        @frames << commands.dup
      end

      def poll_event : UIEvent?
        @events.shift?
      end

      def last_commands : Array(DrawCommand)
        @frames.last? || [] of DrawCommand
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
      getter uri : String
      getter title : String
      getter cursor : Int32
      getter active : Bool
      getter entries : Array(EntrySnapshot)
      getter marked_paths : Array(String)

      def initialize(snapshot : PanelSnapshot)
        @index = snapshot.index
        @path = snapshot.path
        @uri = snapshot.uri
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

    struct TabView
      getter index : Int32
      getter title : String
      getter active : Bool
      getter panel_count : Int32
      getter active_panel : Int32
      getter panel_uris : Array(String)

      def initialize(snapshot : TabSnapshot)
        @index = snapshot.index
        @title = snapshot.title
        @active = snapshot.active
        @panel_count = snapshot.panel_count
        @active_panel = snapshot.active_panel
        @panel_uris = snapshot.panel_uris
      end
    end

    struct WorkspaceView
      getter active_tab : Int32
      getter active_panel : Int32
      getter status_text : String
      getter panels : Array(FilePanelView)
      getter tabs : Array(TabView)
      getter command_ids : Array(String)
      getter external_view : ExternalViewRequest?

      def initialize(snapshot : AppSnapshot)
        @active_tab = snapshot.active_tab
        @active_panel = snapshot.active_panel
        @status_text = snapshot.status_text
        @panels = snapshot.panels.map { |panel| FilePanelView.new(panel) }
        @tabs = snapshot.tabs.map { |tab| TabView.new(tab) }
        @command_ids = snapshot.commands.map(&.id)
        @external_view = snapshot.external_view.try { |view| ExternalViewRequest.from_snapshot(view) }
      end
    end

    def self.workspace(snapshot : AppSnapshot) : WorkspaceView
      WorkspaceView.new(snapshot)
    end

    module WorkspaceRenderer
      extend self

      MENU_ITEMS = ["Left", "File", "Command", "Options", "Right"]

      def render(view : WorkspaceView, bounds : Rect, theme : Theme = Theme.new) : DrawFrame
        commands = [] of DrawCommand
        commands << DrawCommand.fill_rect(bounds, theme.background, "workspace.background")
        render_menu(commands, bounds, theme)

        top = bounds.y + 1
        if view.tabs.any?
          render_tabs(commands, view, Rect.new(bounds.x, top, bounds.width, 1), theme)
          top += 1
        end

        status_height = 2
        panel_height = Math.max(0, bounds.height - (top - bounds.y) - status_height)
        render_panels(commands, view, Rect.new(bounds.x, top, bounds.width, panel_height), theme)
        render_status(commands, view, Rect.new(bounds.x, bounds.y + bounds.height - status_height, bounds.width, status_height), theme)

        DrawFrame.new(bounds, theme, commands)
      end

      private def render_menu(commands : Array(DrawCommand), bounds : Rect, theme : Theme) : Nil
        commands << DrawCommand.fill_rect(Rect.new(bounds.x, bounds.y, bounds.width, 1), theme.accent, "menu.background")
        x = bounds.x
        MENU_ITEMS.each do |item|
          width = item.size + 4
          commands << DrawCommand.text(Rect.new(x, bounds.y, width, 1), item, theme.status, "menu.item")
          x += width
        end
      end

      private def render_tabs(commands : Array(DrawCommand), view : WorkspaceView, rect : Rect, theme : Theme) : Nil
        commands << DrawCommand.fill_rect(rect, theme.header, "tabs.background")
        x = rect.x
        view.tabs.each do |tab|
          label = tab.active ? "[#{tab.title}]" : " #{tab.title} "
          width = Math.min(Math.max(label.size + 2, 8), Math.max(0, rect.x + rect.width - x))
          break if width <= 0

          color = tab.active ? theme.selection : theme.foreground
          style = tab.active ? "tab.active" : "tab.inactive"
          commands << DrawCommand.text(Rect.new(x, rect.y, width, 1), label, color, style)
          x += width
        end
      end

      private def render_panels(commands : Array(DrawCommand), view : WorkspaceView, rect : Rect, theme : Theme) : Nil
        panel_count = Math.max(view.panels.size, 1)
        panel_width = Math.max(1, rect.width // panel_count)
        view.panels.each_with_index do |panel, idx|
          x = rect.x + idx * panel_width
          width = idx == view.panels.size - 1 ? rect.x + rect.width - x : panel_width
          render_panel(commands, panel, Rect.new(x, rect.y, width, rect.height), theme)
        end
      end

      private def render_panel(commands : Array(DrawCommand), panel : FilePanelView, rect : Rect, theme : Theme) : Nil
        return if rect.width <= 0 || rect.height <= 0

        commands << DrawCommand.stroke_rect(rect, theme.border, panel.active ? "panel.active.border" : "panel.border")
        commands << DrawCommand.text(Rect.new(rect.x + 1, rect.y, Math.max(1, rect.width - 2), 1), panel.title, theme.accent, "panel.title")
        header_y = rect.y + 1
        commands << DrawCommand.fill_rect(Rect.new(rect.x + 1, header_y, Math.max(0, rect.width - 2), 1), theme.header, "panel.header.background")
        commands << DrawCommand.text(Rect.new(rect.x + 2, header_y, Math.max(1, rect.width - 4), 1), "Name", theme.foreground, "panel.header.name")
        commands << DrawCommand.text(Rect.new(rect.x + Math.max(2, rect.width - 24), header_y, 8, 1), "Size", theme.foreground, "panel.header.size")
        commands << DrawCommand.text(Rect.new(rect.x + Math.max(2, rect.width - 14), header_y, 12, 1), "Modify time", theme.foreground, "panel.header.modified")

        body_top = header_y + 1
        max_rows = Math.max(0, rect.height - 4)
        panel.entries.first(max_rows).each_with_index do |entry, row|
          y = body_top + row
          if row == panel.cursor
            commands << DrawCommand.fill_rect(Rect.new(rect.x + 1, y, Math.max(0, rect.width - 2), 1), theme.selection, "panel.selection")
          end

          color = row == panel.cursor ? theme.status : theme.foreground
          name_width = Math.max(1, rect.width - 28)
          commands << DrawCommand.text(Rect.new(rect.x + 2, y, name_width, 1), entry.name, color, "panel.entry.name")
          commands << DrawCommand.text(Rect.new(rect.x + Math.max(2, rect.width - 24), y, 8, 1), entry.size, color, "panel.entry.size")
          commands << DrawCommand.text(Rect.new(rect.x + Math.max(2, rect.width - 14), y, 12, 1), entry.modified, color, "panel.entry.modified")
        end
      end

      private def render_status(commands : Array(DrawCommand), view : WorkspaceView, rect : Rect, theme : Theme) : Nil
        return if rect.height <= 0

        selected = view.panels.find(&.active).try(&.selected_entry).try(&.name) || ""
        commands << DrawCommand.fill_rect(Rect.new(rect.x, rect.y, rect.width, 1), theme.background, "status.selected.background")
        commands << DrawCommand.text(Rect.new(rect.x + 1, rect.y, Math.max(1, rect.width - 2), 1), selected, theme.foreground, "status.selected")

        if rect.height > 1
          commands << DrawCommand.fill_rect(Rect.new(rect.x, rect.y + 1, rect.width, 1), theme.accent, "status.background")
          commands << DrawCommand.text(Rect.new(rect.x + 1, rect.y + 1, Math.max(1, rect.width - 2), 1), view.status_text, theme.status, "status.text")
        end
      end
    end
  end
end

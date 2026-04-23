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

    struct TerminalCell
      getter char : Char
      getter foreground : String?
      getter background : String?
      getter style : String?

      def initialize(@char : Char = ' ', @foreground : String? = nil, @background : String? = nil, @style : String? = nil)
      end
    end

    class TerminalGridBackend < Backend
      getter width : Int32
      getter height : Int32
      getter cells : Array(Array(TerminalCell))

      def initialize(@width : Int32, @height : Int32, name : String = "terminal-grid", theme : Theme = Theme.new, events : Array(UIEvent) = [] of UIEvent)
        super(name, theme)
        @events = events
        @cells = Array(Array(TerminalCell)).new(@height) { Array(TerminalCell).new(@width) { TerminalCell.new } }
      end

      def draw(commands : Array(DrawCommand)) : Nil
        clear
        commands.each { |command| apply(command) }
      end

      def poll_event : UIEvent?
        @events.shift?
      end

      def rendered_lines : Array(String)
        @cells.map { |row| row.map(&.char).join.rstrip }
      end

      private def clear : Nil
        @height.times do |y|
          @width.times do |x|
            @cells[y][x] = TerminalCell.new
          end
        end
      end

      private def apply(command : DrawCommand) : Nil
        rect = command.rect
        return unless rect

        case command.kind
        when DrawKind::FillRect
          fill(rect, ' ', background: command.color, style: command.style)
        when DrawKind::StrokeRect
          stroke(rect, foreground: command.color, style: command.style)
        when DrawKind::Text
          write_text(rect, command.text || "", foreground: command.color, style: command.style)
        when DrawKind::Line
          fill(rect, rect.width == 1 ? '|' : '-', foreground: command.color, style: command.style)
        when DrawKind::Clip, DrawKind::Image
          nil
        end
      end

      private def fill(rect : Rect, char : Char, foreground : String? = nil, background : String? = nil, style : String? = nil) : Nil
        each_cell(rect) do |x, y|
          @cells[y][x] = TerminalCell.new(char, foreground, background, style)
        end
      end

      private def stroke(rect : Rect, foreground : String? = nil, style : String? = nil) : Nil
        return if rect.width <= 0 || rect.height <= 0

        right = rect.x + rect.width - 1
        bottom = rect.y + rect.height - 1
        each_cell(rect) do |x, y|
          next unless x == rect.x || x == right || y == rect.y || y == bottom

          char = if (x == rect.x || x == right) && (y == rect.y || y == bottom)
                   '+'
                 elsif y == rect.y || y == bottom
                   '-'
                 else
                   '|'
                 end
          @cells[y][x] = TerminalCell.new(char, foreground, nil, style)
        end
      end

      private def write_text(rect : Rect, text : String, foreground : String? = nil, style : String? = nil) : Nil
        return if rect.width <= 0 || rect.height <= 0

        y = rect.y
        return if y < 0 || y >= @height

        text.each_char.first(rect.width).each_with_index do |char, idx|
          x = rect.x + idx
          next if x < 0 || x >= @width

          @cells[y][x] = TerminalCell.new(char, foreground, nil, style)
        end
      end

      private def each_cell(rect : Rect, &block : Int32, Int32 -> Nil) : Nil
        start_x = Math.max(0, rect.x)
        start_y = Math.max(0, rect.y)
        end_x = Math.min(@width, rect.x + rect.width)
        end_y = Math.min(@height, rect.y + rect.height)
        return if start_x >= end_x || start_y >= end_y

        y = start_y
        while y < end_y
          x = start_x
          while x < end_x
            yield x, y
            x += 1
          end
          y += 1
        end
      end
    end

    struct RenderContext
      getter theme : Theme

      def initialize(@theme : Theme = Theme.new)
      end
    end

    abstract class Widget
      getter id : String
      property bounds : Rect
      getter children : Array(Widget)

      def initialize(@id : String, @bounds : Rect = Rect.new(0, 0, 0, 0), @children : Array(Widget) = [] of Widget)
      end

      def layout(bounds : Rect) : self
        @bounds = bounds
        self
      end

      def render(context : RenderContext, commands : Array(DrawCommand)) : Nil
        @children.each(&.render(context, commands))
      end

      def render_frame(bounds : Rect, theme : Theme = Theme.new) : DrawFrame
        commands = [] of DrawCommand
        layout(bounds)
        render(RenderContext.new(theme), commands)
        DrawFrame.new(bounds, theme, commands)
      end
    end

    class Label < Widget
      property text : String
      property color : String?
      property style : String?

      def initialize(@text : String, id : String = "label", color : String? = nil, style : String? = nil)
        super(id)
        @color = color
        @style = style
      end

      def render(context : RenderContext, commands : Array(DrawCommand)) : Nil
        commands << DrawCommand.text(@bounds, @text, @color || context.theme.foreground, @style || "label")
        super(context, commands)
      end
    end

    struct ListItem
      getter columns : Array(String)
      getter selected : Bool
      getter metadata : Hash(String, String)

      def initialize(@columns : Array(String), @selected : Bool = false, @metadata : Hash(String, String) = {} of String => String)
      end
    end

    class ListView < Widget
      getter headers : Array(String)
      getter items : Array(ListItem)

      def initialize(@headers : Array(String), @items : Array(ListItem), id : String = "list-view")
        super(id)
      end

      def render(context : RenderContext, commands : Array(DrawCommand)) : Nil
        theme = context.theme
        commands << DrawCommand.fill_rect(Rect.new(@bounds.x, @bounds.y, @bounds.width, 1), theme.header, "#{@id}.header.background")
        render_columns(commands, @headers, @bounds.y, theme.foreground, "#{@id}.header")

        max_rows = Math.max(0, @bounds.height - 1)
        @items.first(max_rows).each_with_index do |item, row|
          y = @bounds.y + 1 + row
          color = item.selected ? theme.status : theme.foreground
          if item.selected
            commands << DrawCommand.fill_rect(Rect.new(@bounds.x, y, @bounds.width, 1), theme.selection, "#{@id}.selection")
          end
          render_columns(commands, item.columns, y, color, "#{@id}.item")
        end

        super(context, commands)
      end

      private def render_columns(commands : Array(DrawCommand), columns : Array(String), y : Int32, color : String, style : String) : Nil
        return if @bounds.width <= 0 || columns.empty?

        if columns.size == 1
          commands << DrawCommand.text(Rect.new(@bounds.x, y, @bounds.width, 1), columns.first, color, style)
          return
        end

        fixed_tail = Math.min(24, @bounds.width // 2)
        first_width = Math.max(1, @bounds.width - fixed_tail)
        commands << DrawCommand.text(Rect.new(@bounds.x, y, first_width, 1), columns[0], color, "#{style}.0")

        tail_columns = columns[1..]
        tail_width = Math.max(1, fixed_tail // tail_columns.size)
        tail_columns.each_with_index do |column, idx|
          x = @bounds.x + first_width + idx * tail_width
          width = idx == tail_columns.size - 1 ? @bounds.x + @bounds.width - x : tail_width
          commands << DrawCommand.text(Rect.new(x, y, Math.max(1, width), 1), column, color, "#{style}.#{idx + 1}")
        end
      end
    end

    class TabBar < Widget
      getter tabs : Array(TabView)

      def initialize(@tabs : Array(TabView), id : String = "tab-bar")
        super(id)
      end

      def render(context : RenderContext, commands : Array(DrawCommand)) : Nil
        theme = context.theme
        commands << DrawCommand.fill_rect(@bounds, theme.header, "#{@id}.background")
        x = @bounds.x
        @tabs.each do |tab|
          label = tab.active ? "[#{tab.title}]" : " #{tab.title} "
          width = Math.min(Math.max(label.size + 2, 8), Math.max(0, @bounds.x + @bounds.width - x))
          break if width <= 0

          color = tab.active ? theme.selection : theme.foreground
          style = tab.active ? "#{@id}.active" : "#{@id}.inactive"
          commands << DrawCommand.text(Rect.new(x, @bounds.y, width, 1), label, color, style)
          x += width
        end
        super(context, commands)
      end
    end

    class Split < Widget
      enum Direction
        Horizontal
        Vertical
      end

      getter direction : Direction

      def initialize(@direction : Direction, children : Array(Widget), id : String = "split")
        super(id, children: children)
      end

      def layout(bounds : Rect) : self
        super(bounds)
        return self if @children.empty?

        if @direction.horizontal?
          child_width = Math.max(1, bounds.width // @children.size)
          @children.each_with_index do |child, idx|
            x = bounds.x + idx * child_width
            width = idx == @children.size - 1 ? bounds.x + bounds.width - x : child_width
            child.layout(Rect.new(x, bounds.y, width, bounds.height))
          end
        else
          child_height = Math.max(1, bounds.height // @children.size)
          @children.each_with_index do |child, idx|
            y = bounds.y + idx * child_height
            height = idx == @children.size - 1 ? bounds.y + bounds.height - y : child_height
            child.layout(Rect.new(bounds.x, y, bounds.width, height))
          end
        end
        self
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

    struct ViewerSessionView
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

      def initialize(snapshot : ViewerSessionSnapshot)
        @id = snapshot.id
        @panel_index = snapshot.panel_index
        @path = snapshot.path
        @title = snapshot.title
        @mode = snapshot.mode
        @scroll_offset = snapshot.scroll_offset
        @cursor_line = snapshot.cursor_line
        @cursor_col = snapshot.cursor_col
        @search_term = snapshot.search_term
        @dirty = snapshot.dirty
        @readonly = snapshot.readonly
        @truncated = snapshot.truncated
        @error = snapshot.error
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
      getter viewer_config : ViewerConfigSnapshot
      getter viewer_sessions : Array(ViewerSessionView)
      getter command_ids : Array(String)
      getter external_view : ExternalViewRequest?

      def initialize(snapshot : AppSnapshot)
        @active_tab = snapshot.active_tab
        @active_panel = snapshot.active_panel
        @status_text = snapshot.status_text
        @panels = snapshot.panels.map { |panel| FilePanelView.new(panel) }
        @tabs = snapshot.tabs.map { |tab| TabView.new(tab) }
        @viewer_config = snapshot.viewer_config
        @viewer_sessions = snapshot.viewer_sessions.map { |session| ViewerSessionView.new(session) }
        @command_ids = snapshot.commands.map(&.id)
        @external_view = snapshot.external_view.try { |view| ExternalViewRequest.from_snapshot(view) }
      end
    end

    def self.workspace(snapshot : AppSnapshot) : WorkspaceView
      WorkspaceView.new(snapshot)
    end

    class FilePanelWidget < Widget
      getter panel : FilePanelView

      def initialize(@panel : FilePanelView, id : String? = nil)
        id ||= "file-panel-#{@panel.index}"
        super(id)
      end

      def render(context : RenderContext, commands : Array(DrawCommand)) : Nil
        theme = context.theme
        commands << DrawCommand.stroke_rect(@bounds, theme.border, @panel.active ? "#{@id}.active.border" : "#{@id}.border")
        commands << DrawCommand.text(Rect.new(@bounds.x + 1, @bounds.y, Math.max(1, @bounds.width - 2), 1), @panel.title, theme.accent, "#{@id}.title")

        list_bounds = Rect.new(@bounds.x + 1, @bounds.y + 1, Math.max(0, @bounds.width - 2), Math.max(0, @bounds.height - 2))
        list_items = @panel.entries.map_with_index do |entry, row|
          ListItem.new([entry.name, entry.size, entry.modified], selected: row == @panel.cursor, metadata: {"uri" => entry.uri})
        end
        ListView.new(["Name", "Size", "Modify time"], list_items, id: "#{@id}.list").layout(list_bounds).render(context, commands)
        super(context, commands)
      end
    end

    class StatusBar < Widget
      getter view : WorkspaceView

      def initialize(@view : WorkspaceView, id : String = "status-bar")
        super(id)
      end

      def render(context : RenderContext, commands : Array(DrawCommand)) : Nil
        theme = context.theme
        selected = @view.panels.find(&.active).try(&.selected_entry).try(&.name) || ""
        commands << DrawCommand.fill_rect(Rect.new(@bounds.x, @bounds.y, @bounds.width, 1), theme.background, "#{@id}.selected.background")
        commands << DrawCommand.text(Rect.new(@bounds.x + 1, @bounds.y, Math.max(1, @bounds.width - 2), 1), selected, theme.foreground, "#{@id}.selected")

        if @bounds.height > 1
          commands << DrawCommand.fill_rect(Rect.new(@bounds.x, @bounds.y + 1, @bounds.width, 1), theme.accent, "#{@id}.background")
          commands << DrawCommand.text(Rect.new(@bounds.x + 1, @bounds.y + 1, Math.max(1, @bounds.width - 2), 1), @view.status_text, theme.status, "#{@id}.text")
        end
        super(context, commands)
      end
    end

    class WorkspaceWidget < Widget
      getter view : WorkspaceView

      def initialize(@view : WorkspaceView, id : String = "workspace")
        super(id)
        panel_widgets = @view.panels.map { |panel| FilePanelWidget.new(panel).as(Widget) }
        @tab_bar = TabBar.new(@view.tabs)
        @panel_split = Split.new(Split::Direction::Horizontal, panel_widgets, id: "workspace-panels")
        @status_bar = StatusBar.new(@view)
        @children = [@tab_bar.as(Widget), @panel_split.as(Widget), @status_bar.as(Widget)]
      end

      def layout(bounds : Rect) : self
        super(bounds)
        top = bounds.y
        tab_height = @view.tabs.any? ? 1 : 0
        @tab_bar.layout(Rect.new(bounds.x, top, bounds.width, tab_height))
        top += tab_height
        status_height = 2
        panel_height = Math.max(0, bounds.height - tab_height - status_height)
        @panel_split.layout(Rect.new(bounds.x, top, bounds.width, panel_height))
        @status_bar.layout(Rect.new(bounds.x, bounds.y + bounds.height - status_height, bounds.width, status_height))
        self
      end

      def render(context : RenderContext, commands : Array(DrawCommand)) : Nil
        commands << DrawCommand.fill_rect(@bounds, context.theme.background, "#{@id}.background")
        @children.each(&.render(context, commands))
      end
    end

    module WorkspaceRenderer
      extend self

      MENU_ITEMS = ["Left", "File", "Command", "Options", "Right"]

      def render(view : WorkspaceView, bounds : Rect, theme : Theme = Theme.new) : DrawFrame
        frame = WorkspaceWidget.new(view).render_frame(Rect.new(bounds.x, bounds.y + 1, bounds.width, Math.max(0, bounds.height - 1)), theme)
        commands = frame.commands
        render_menu(commands, bounds, theme)
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

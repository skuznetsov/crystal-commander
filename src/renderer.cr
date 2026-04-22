module Commander
  ROW_FLAG_DIRECTORY  = 1_u32
  ROW_FLAG_EXECUTABLE = 2_u32
  ROW_FLAG_PARENT     = 4_u32
  ROW_FLAG_MARKED     = 8_u32

  enum EventType : Int32
    None        = 0
    Key         = 1
    MouseDown   = 2
    RowSelected = 3
    RowActivated = 4
    Tab         = 5
    WindowClose = 6
    Quit        = 7
  end

  lib LibRenderer
    struct RenderRow
      name : UInt8*
      size : UInt8*
      modified : UInt8*
      flags : UInt32
    end

    struct RenderEvent
      type : Int32
      panel : Int32
      key_code : Int32
      modifiers : UInt32
      row : Int32
      button : Int32
      click_count : UInt32
      x : Float64
      y : Float64
    end

    fun commander_renderer_create(panel_count : Int32, width : Int32, height : Int32) : Void*
    fun commander_renderer_destroy(handle : Void*) : Void
    fun commander_renderer_show(handle : Void*) : Int32
    fun commander_renderer_pump(handle : Void*, wait_ms : Int32) : Int32
    fun commander_renderer_stop(handle : Void*) : Void
    fun commander_renderer_poll_event(handle : Void*, out_event : RenderEvent*) : Int32
    fun commander_renderer_set_active_panel(handle : Void*, panel_index : Int32) : Void
    fun commander_renderer_set_status_text(handle : Void*, text : UInt8*) : Void
    fun commander_renderer_set_panel_path(handle : Void*, panel_index : Int32, path : UInt8*) : Void
    fun commander_renderer_set_panel_rows(handle : Void*, panel_index : Int32, rows : RenderRow*, row_count : Int32, cursor : Int32) : Void
    fun commander_renderer_set_panel_cursor(handle : Void*, panel_index : Int32, selected_index : Int32) : Void
    fun commander_renderer_get_mouse_position(handle : Void*, x : Float64*, y : Float64*) : Void
    fun commander_renderer_set_mouse_visible(visible : Int32) : Void
  end

  struct Row
    getter name : String
    getter size : String
    getter modified : String
    getter flags : UInt32

    def initialize(@name : String, @size : String, @modified : String, @flags : UInt32 = 0_u32)
    end
  end

  record Event,
    type : EventType,
    panel : Int32,
    key_code : Int32,
    modifiers : UInt32,
    row : Int32,
    button : Int32,
    click_count : UInt32,
    x : Float64,
    y : Float64

  class Renderer
    @handle : Void*
    @destroyed : Bool
    getter panel_count : Int32

    def initialize(@panel_count : Int32 = 3, width : Int32 = 1360, height : Int32 = 860)
      @handle = LibRenderer.commander_renderer_create(@panel_count, width, height)
      raise "renderer allocation failed" if @handle.null?
      @destroyed = false
    end

    def show : Bool
      return false if @destroyed
      LibRenderer.commander_renderer_show(@handle) == 1
    end

    def pump(wait_ms : Int32 = 16) : Bool
      return false if @destroyed
      LibRenderer.commander_renderer_pump(@handle, wait_ms) == 1
    end

    def stop : Nil
      return if @destroyed
      LibRenderer.commander_renderer_stop(@handle)
    end

    def poll_event : Event?
      return nil if @destroyed
      raw = LibRenderer::RenderEvent.new
      return nil unless LibRenderer.commander_renderer_poll_event(@handle, pointerof(raw)) == 1

      type = EventType.from_value?(raw.type) || EventType::None
      Event.new(
        type: type,
        panel: raw.panel,
        key_code: raw.key_code,
        modifiers: raw.modifiers,
        row: raw.row,
        button: raw.button,
        click_count: raw.click_count,
        x: raw.x,
        y: raw.y
      )
    end

    def set_active_panel(panel_index : Int32) : Nil
      return if @destroyed
      LibRenderer.commander_renderer_set_active_panel(@handle, panel_index)
    end

    def set_status_text(text : String) : Nil
      return if @destroyed
      LibRenderer.commander_renderer_set_status_text(@handle, text.to_unsafe)
    end

    def set_panel_path(panel_index : Int32, path : String) : Nil
      return if @destroyed
      LibRenderer.commander_renderer_set_panel_path(@handle, panel_index, path.to_unsafe)
    end

    def set_panel_rows(panel_index : Int32, rows : Array(Row), cursor : Int32) : Nil
      return if @destroyed

      if rows.empty?
        LibRenderer.commander_renderer_set_panel_rows(@handle, panel_index, Pointer(LibRenderer::RenderRow).null, 0, 0)
        return
      end

      names = rows.map(&.name)
      sizes = rows.map(&.size)
      modified = rows.map(&.modified)
      native = rows.map_with_index do |row, idx|
        native_row = LibRenderer::RenderRow.new
        native_row.name = names[idx].to_unsafe
        native_row.size = sizes[idx].to_unsafe
        native_row.modified = modified[idx].to_unsafe
        native_row.flags = row.flags
        native_row
      end

      LibRenderer.commander_renderer_set_panel_rows(@handle, panel_index, native.to_unsafe, native.size.to_i32, cursor)
    end

    def set_panel_cursor(panel_index : Int32, selected_index : Int32) : Nil
      return if @destroyed
      LibRenderer.commander_renderer_set_panel_cursor(@handle, panel_index, selected_index)
    end

    def mouse_position : {Float64, Float64}
      x = 0.0
      y = 0.0
      unless @destroyed
        LibRenderer.commander_renderer_get_mouse_position(@handle, pointerof(x), pointerof(y))
      end
      {x, y}
    end

    def mouse_visible=(visible : Bool) : Nil
      LibRenderer.commander_renderer_set_mouse_visible(visible ? 1 : 0)
    end

    def destroy : Nil
      return if @destroyed
      LibRenderer.commander_renderer_destroy(@handle)
      @handle = Pointer(Void).null
      @destroyed = true
    end

    def finalize : Nil
      destroy
    end
  end
end

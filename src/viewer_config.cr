require "./file_preview"
require "./snapshots"

module Commander
  struct ViewerConfig
    DEFAULT_TAB_WIDTH = 4

    getter external_viewer : String?
    getter external_editor : String?
    getter max_buffer_size : Int64
    getter tab_width : Int32
    getter show_line_numbers : Bool
    getter word_wrap : Bool

    def initialize(
      @external_viewer : String? = nil,
      @external_editor : String? = nil,
      @max_buffer_size : Int64 = FilePreview::MAX_BYTES.to_i64,
      @tab_width : Int32 = DEFAULT_TAB_WIDTH,
      @show_line_numbers : Bool = false,
      @word_wrap : Bool = false
    )
    end

    def self.from_env(env : ENV.class = ENV) : ViewerConfig
      max_buffer_size = env["COMMANDER_VIEWER_MAX_BYTES"]?.try(&.to_i64?) || FilePreview::MAX_BYTES.to_i64
      tab_width = env["COMMANDER_VIEWER_TAB_WIDTH"]?.try(&.to_i?) || DEFAULT_TAB_WIDTH

      new(
        external_viewer: blank_to_nil(env["COMMANDER_EXTERNAL_VIEWER"]?),
        external_editor: blank_to_nil(env["COMMANDER_EXTERNAL_EDITOR"]?),
        max_buffer_size: max_buffer_size < 1 ? FilePreview::MAX_BYTES.to_i64 : max_buffer_size,
        tab_width: tab_width < 1 ? DEFAULT_TAB_WIDTH : tab_width,
        show_line_numbers: truthy?(env["COMMANDER_VIEWER_LINE_NUMBERS"]?),
        word_wrap: truthy?(env["COMMANDER_VIEWER_WORD_WRAP"]?)
      )
    end

    def preview_max_bytes : Int32
      return Int32::MAX if @max_buffer_size > Int32::MAX

      @max_buffer_size.to_i32
    end

    def to_snapshot : ViewerConfigSnapshot
      ViewerConfigSnapshot.new(
        external_viewer: @external_viewer,
        external_editor: @external_editor,
        max_buffer_size: @max_buffer_size,
        tab_width: @tab_width,
        show_line_numbers: @show_line_numbers,
        word_wrap: @word_wrap
      )
    end

    private def self.blank_to_nil(value : String?) : String?
      return nil unless value

      stripped = value.strip
      stripped.empty? ? nil : stripped
    end

    private def self.truthy?(value : String?) : Bool
      return false unless value

      case value.downcase
      when "1", "true", "yes", "on"
        true
      else
        false
      end
    end
  end
end

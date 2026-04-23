require "./renderer"
require "./snapshots"
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
  getter uri : String
  getter flags : UInt32

  def initialize(@name : String, @size : String, @modified : String, @path : String, @flags : UInt32, uri : String? = nil)
    @uri = uri || Commander::VirtualFS::VirtualPath.parse(@path).to_uri
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
      uri: @uri
    )
  end
end

class PanelState
  record ReturnOffset, parent_path : String, child_path : String, cursor : Int32

  getter path : String
  getter location : Commander::VirtualFS::VirtualPath
  getter entries : Array(PanelEntry)
  getter marked_paths : Set(String)
  property cursor : Int32

  def initialize(start_path : String)
    @path = start_path
    @location = Commander::VirtualFS::VirtualPath.parse(start_path)
    @entries = [] of PanelEntry
    @marked_paths = Set(String).new
    @return_offsets = [] of ReturnOffset
    @cursor = 0
    load_path(start_path)
  end

  def load_path(path : String) : Nil
    provider = Commander::VirtualFS::FileProvider.new
    requested = Commander::VirtualFS::VirtualPath.parse(path)
    normalized = requested.local? ? File.expand_path(requested.path) : home_dir
    stat = provider.stat(Commander::VirtualFS::VirtualPath.parse(normalized))
    stat_entry = stat.entries.first?
    normalized = home_dir unless stat.ok && stat_entry && stat_entry.kind == Commander::VirtualFS::EntryKind::Directory

    @path = normalized
    @location = Commander::VirtualFS::VirtualPath.parse(normalized)
    @entries.clear

    parent = File.dirname(@path)
    if parent != @path
      @entries << PanelEntry.new(
        name: "/..",
        size: "UP--DIR",
        modified: Time.local.to_s("%b %-d %H:%M"),
        path: parent,
        flags: Commander::ROW_FLAG_DIRECTORY | Commander::ROW_FLAG_PARENT,
        uri: Commander::VirtualFS::VirtualPath.parse(parent).to_uri
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
        flags: flags,
        uri: entry.path.to_uri
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
      uri: @location.to_uri
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

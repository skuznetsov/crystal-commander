require "file_utils"
require "spec"
require "../src/panel_state"

private def with_panel_tree
  root = File.join(Dir.tempdir, "commander-panel-state-#{Process.pid}-#{Random.new.hex(4)}")
  Dir.mkdir_p(File.join(root, "alpha"))
  Dir.mkdir_p(File.join(root, "bravo"))
  Dir.mkdir_p(File.join(root, "charlie"))
  File.write(File.join(root, "alpha", "inside.txt"), "alpha")
  File.write(File.join(root, "bravo", "inside.txt"), "bravo")
  yield root
ensure
  FileUtils.rm_rf(root) if root
end

private def cursor_for_path(panel : PanelState, path : String) : Int32
  row = panel.entries.index { |entry| entry.path == path }
  row.should_not be_nil
  row.not_nil!.to_i32
end

describe PanelState do
  it "restores the child directory row when returning to a parent directory" do
    with_panel_tree do |root|
      alpha = File.join(root, "alpha")
      panel = PanelState.new(root)
      alpha_row = cursor_for_path(panel, alpha)

      panel.move_cursor_to(alpha_row)
      panel.enter_directory(alpha).should be_true
      panel.path.should eq(alpha)

      panel.go_parent.should be_true
      panel.path.should eq(root)
      panel.cursor.should eq(alpha_row)
      panel.selected.not_nil!.path.should eq(alpha)
    end
  end

  it "keeps independent return offsets for sibling directories" do
    with_panel_tree do |root|
      alpha = File.join(root, "alpha")
      bravo = File.join(root, "bravo")
      panel = PanelState.new(root)
      alpha_row = cursor_for_path(panel, alpha)
      bravo_row = cursor_for_path(panel, bravo)

      panel.move_cursor_to(alpha_row)
      panel.enter_directory(alpha).should be_true
      panel.go_parent.should be_true
      panel.cursor.should eq(alpha_row)

      panel.move_cursor_to(bravo_row)
      panel.enter_directory(bravo).should be_true
      panel.go_parent.should be_true
      panel.cursor.should eq(bravo_row)

      panel.enter_directory(bravo).should be_true
      panel.go_parent.should be_true
      panel.cursor.should eq(bravo_row)
    end
  end
end

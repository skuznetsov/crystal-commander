require "spec"
require "../src/viewer_config"

describe Commander::ViewerConfig do
  it "uses safe defaults" do
    config = Commander::ViewerConfig.new

    config.external_viewer.should be_nil
    config.external_editor.should be_nil
    config.max_buffer_size.should eq(Commander::FilePreview::MAX_BYTES)
    config.tab_width.should eq(4)
    config.show_line_numbers.should be_false
    config.word_wrap.should be_false
  end

  it "serializes to snapshots for automation and UI projection" do
    snapshot = Commander::ViewerConfig.new(
      external_viewer: "open",
      external_editor: "vim",
      max_buffer_size: 1024_i64,
      tab_width: 2,
      show_line_numbers: true,
      word_wrap: true
    ).to_snapshot

    snapshot.external_viewer.should eq("open")
    snapshot.external_editor.should eq("vim")
    snapshot.max_buffer_size.should eq(1024)
    snapshot.tab_width.should eq(2)
    snapshot.show_line_numbers.should be_true
    snapshot.word_wrap.should be_true
  end
end

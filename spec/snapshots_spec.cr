require "spec"
require "json"
require "../src/snapshots"

describe "Commander snapshots" do
  it "CommandSnapshot roundtrips JSON" do
    s = Commander::CommandSnapshot.new("id1", "Title", "desc", "plug")
    json = s.to_json
    r = Commander::CommandSnapshot.from_json(json)
    r.id.should eq("id1")
    r.plugin_id.should eq("plug")
    r.mutating.should be_false
  end

  it "PreviewSnapshot holds error or content" do
    err = Commander::PreviewSnapshot.new("/p", "t", "", false, "e")
    err.error.should eq("e")
    ok = Commander::PreviewSnapshot.new("/p", "t", "c", true, nil)
    ok.truncated.should be_true
  end

  it "ViewerSessionSnapshot tracks read-only viewer state" do
    session = Commander::ViewerSessionSnapshot.new(
      id: "viewer-1",
      panel_index: 0,
      path: "/tmp/readme.txt",
      title: "readme.txt"
    )

    session.readonly.should be_true
    session.dirty.should be_false
    session.with_scroll_offset(12).scroll_offset.should eq(12)
    searched = session.with_search("needle", 4, 2)
    searched.search_term.should eq("needle")
    searched.cursor_line.should eq(4)
    searched.cursor_col.should eq(2)
  end

  it "ViewerConfigSnapshot roundtrips JSON" do
    config = Commander::ViewerConfigSnapshot.new(
      external_viewer: "open",
      external_editor: "vim",
      max_buffer_size: 1024_i64,
      tab_width: 2,
      show_line_numbers: true,
      word_wrap: true
    )
    parsed = Commander::ViewerConfigSnapshot.from_json(config.to_json)

    parsed.external_viewer.should eq("open")
    parsed.external_editor.should eq("vim")
    parsed.max_buffer_size.should eq(1024)
    parsed.tab_width.should eq(2)
    parsed.show_line_numbers.should be_true
    parsed.word_wrap.should be_true
  end

  it "OperationPlanSnapshot summary via kind" do
    plan = Commander::OperationPlanSnapshot.new("Copy", 0, nil, ["a"], "tgt", "Copy 1 item(s) to tgt")
    plan.kind.should eq("Copy")
  end
end

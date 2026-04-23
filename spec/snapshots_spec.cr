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

  it "OperationPlanSnapshot summary via kind" do
    plan = Commander::OperationPlanSnapshot.new("Copy", 0, nil, ["a"], "tgt", "Copy 1 item(s) to tgt")
    plan.kind.should eq("Copy")
  end
end

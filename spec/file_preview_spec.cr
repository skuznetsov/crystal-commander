require "spec"
require "../src/file_preview"

describe Commander::FilePreview do
  it "returns error snapshot for non-file path" do
    snap = Commander::FilePreview.load("/this/does/not/exist/xyz")
    snap.error.should_not be_nil
    snap.content.should eq("")
    snap.truncated.should be_false
  end

  it "loads small text file content" do
    with_tempfile("small.txt", "hello world\nline2") do |path|
      snap = Commander::FilePreview.load(path)
      snap.content.should contain("hello world")
      snap.truncated.should be_false
      snap.error.should be_nil
      snap.title.should contain("small.txt")
    end
  end

  it "truncates content larger than MAX_BYTES" do
    large = "x" * (Commander::FilePreview::MAX_BYTES + 100)
    with_tempfile("large.txt", large) do |path|
      snap = Commander::FilePreview.load(path)
      snap.truncated.should be_true
      snap.content.bytesize.should eq(Commander::FilePreview::MAX_BYTES)
    end
  end

  it "uses caller-provided max buffer size" do
    with_tempfile("custom-limit.txt", "abcdef") do |path|
      snap = Commander::FilePreview.load(path, max_bytes: 3)

      snap.truncated.should be_true
      snap.content.should eq("abc")
    end
  end

  it "rejects binary files containing NUL" do
    binary = "text\0more"
    with_tempfile("bin", binary) do |path|
      snap = Commander::FilePreview.load(path)
      error = snap.error
      error.should_not be_nil
      error.not_nil!.should contain("binary")
      snap.content.should eq("")
    end
  end

  it "handles permission errors gracefully" do
    # create file then remove read perm (best effort on mac)
    with_tempfile("noread.txt", "secret") do |path|
      File.chmod(path, 0o000) rescue nil
      begin
        snap = Commander::FilePreview.load(path)
        # either error or content (depends on umask), but should not crash
        (snap.error || snap.content).should_not be_nil
      ensure
        File.chmod(path, 0o644) rescue nil
      end
    end
  end
end

def with_tempfile(name : String, content : String)
  path = File.join(Dir.tempdir, "cmdr_preview_#{Random.new.hex(4)}_#{name}")
  File.write(path, content)
  begin
    yield path
  ensure
    File.delete(path) rescue nil
  end
end

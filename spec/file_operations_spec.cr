require "spec"
require "file_utils"
require "../src/file_operations"

describe Commander::FileOperations do
  describe ".mkdir" do
    it "creates directory and returns success" do
      with_temp_subdir("base") do |base|
        newdir = File.join(base, "newdir")
        res = Commander::FileOperations.mkdir(newdir)
        res.ok.should be_true
        Dir.exists?(newdir).should be_true
      end
    end

    it "fails if path already exists" do
      with_temp_subdir("exists") do |dir|
        # helper already mkdir_p the dir
        res = Commander::FileOperations.mkdir(dir)
        res.ok.should be_false
        res.message.should contain("already exists")
      end
    end
  end

  describe ".copy_file" do
    it "copies file to target dir" do
      with_temp_subdir("copytest") do |base|
        src_dir = File.join(base, "src"); Dir.mkdir(src_dir)
        tgt_dir = File.join(base, "tgt"); Dir.mkdir(tgt_dir)
        src = File.join(src_dir, "file.txt")
        File.write(src, "data123")

        res = Commander::FileOperations.copy_file(src, tgt_dir)
        res.ok.should be_true
        File.exists?(File.join(tgt_dir, "file.txt")).should be_true
      end
    end

    it "fails if source not file" do
      with_temp_subdir("copybad") do |base|
        tgt = File.join(base, "t"); Dir.mkdir(tgt)
        res = Commander::FileOperations.copy_file(base, tgt) # base is dir
        res.ok.should be_false
        res.message.should contain("not a regular file")
      end
    end

    it "fails if target dir missing" do
      with_temp_subdir("copymiss") do |base|
        src = File.join(base, "s.txt"); File.write(src, "x")
        res = Commander::FileOperations.copy_file(src, File.join(base, "nope"))
        res.ok.should be_false
      end
    end
  end
end

def with_temp_subdir(name : String)
  base = File.join(Dir.tempdir, "cmdr_fileop_#{Random.new.hex(4)}")
  Dir.mkdir_p(base)
  sub = File.join(base, name)
  Dir.mkdir_p(sub)
  begin
    yield sub
  ensure
    FileUtils.rm_rf(base) rescue nil
  end
end

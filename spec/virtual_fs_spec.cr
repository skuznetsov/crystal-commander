require "spec"
require "../src/virtual_fs"

describe Commander::VirtualFS::VirtualPath do
  it "parses local paths as file scheme paths" do
    path = Commander::VirtualFS::VirtualPath.parse("/tmp/example")
    path.scheme.should eq("file")
    path.local?.should be_true
    path.path.should eq("/tmp/example")
  end

  it "parses sftp paths with authority" do
    path = Commander::VirtualFS::VirtualPath.parse("sftp://user@example.com/home/user")
    path.scheme.should eq("sftp")
    path.authority.should eq("example.com")
    path.path.should eq("/home/user")
    path.remote?.should be_true
  end

  it "parses ssh paths with authority" do
    path = Commander::VirtualFS::VirtualPath.parse("ssh://host.example.org/etc")
    path.scheme.should eq("ssh")
    path.authority.should eq("host.example.org")
    path.path.should eq("/etc")
  end

  it "parses s3 bucket/key paths" do
    path = Commander::VirtualFS::VirtualPath.parse("s3://my-bucket/prefix/object.txt")
    path.scheme.should eq("s3")
    path.authority.should eq("my-bucket")
    path.path.should eq("/prefix/object.txt")
  end

  it "rejects unsupported schemes" do
    expect_raises(ArgumentError, /unsupported VFS scheme/) do
      Commander::VirtualFS::VirtualPath.parse("ftp://example.com/path")
    end
  end
end

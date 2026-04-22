require "spec"
require "../src/virtual_fs"

private class RecordingVfsProvider < Commander::VirtualFS::Provider
  getter calls = [] of Commander::VirtualFS::Operation

  def scheme : String
    "sftp"
  end

  def stat(path : Commander::VirtualFS::VirtualPath) : Commander::VirtualFS::Response
    record(Commander::VirtualFS::Operation::Stat)
  end

  def list(path : Commander::VirtualFS::VirtualPath) : Commander::VirtualFS::Response
    record(Commander::VirtualFS::Operation::List)
  end

  def read(path : Commander::VirtualFS::VirtualPath) : Commander::VirtualFS::Response
    record(Commander::VirtualFS::Operation::Read)
  end

  def write(path : Commander::VirtualFS::VirtualPath, data : Bytes) : Commander::VirtualFS::Response
    record(Commander::VirtualFS::Operation::Write)
  end

  def mkdir(path : Commander::VirtualFS::VirtualPath) : Commander::VirtualFS::Response
    record(Commander::VirtualFS::Operation::Mkdir)
  end

  def delete(path : Commander::VirtualFS::VirtualPath) : Commander::VirtualFS::Response
    record(Commander::VirtualFS::Operation::Delete)
  end

  def rename(path : Commander::VirtualFS::VirtualPath, target : Commander::VirtualFS::VirtualPath) : Commander::VirtualFS::Response
    record(Commander::VirtualFS::Operation::Rename)
  end

  def copy(path : Commander::VirtualFS::VirtualPath, target : Commander::VirtualFS::VirtualPath) : Commander::VirtualFS::Response
    record(Commander::VirtualFS::Operation::Copy)
  end

  def open_stream(path : Commander::VirtualFS::VirtualPath) : Commander::VirtualFS::Response
    record(Commander::VirtualFS::Operation::OpenStream)
  end

  private def record(operation : Commander::VirtualFS::Operation) : Commander::VirtualFS::Response
    @calls << operation
    Commander::VirtualFS::Response.new(true)
  end
end

describe Commander::VirtualFS::VirtualPath do
  it "parses local paths as file scheme paths" do
    path = Commander::VirtualFS::VirtualPath.parse("/tmp/example")
    path.scheme.should eq("file")
    path.local?.should be_true
    path.path.should eq("/tmp/example")
    path.to_uri.should eq("file:///tmp/example")
  end

  it "parses sftp paths with authority" do
    path = Commander::VirtualFS::VirtualPath.parse("sftp://user@example.com/home/user")
    path.scheme.should eq("sftp")
    path.authority.should eq("user@example.com")
    path.path.should eq("/home/user")
    path.remote?.should be_true
    path.to_uri.should eq("sftp://user@example.com/home/user")
  end

  it "round-trips remote authority with port" do
    path = Commander::VirtualFS::VirtualPath.parse("ssh://user@example.com:2222/home/user")
    path.scheme.should eq("ssh")
    path.authority.should eq("user@example.com:2222")
    path.path.should eq("/home/user")
    path.to_uri.should eq("ssh://user@example.com:2222/home/user")
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
    error = expect_raises(Commander::VirtualFS::VfsException) do
      Commander::VirtualFS::VirtualPath.parse("ftp://example.com/path")
    end
    error.vfs_error.code.should eq(Commander::VirtualFS::ErrorCode::UnsupportedScheme)
  end
end

describe Commander::VirtualFS::Registry do
  it "dispatches every operation through the registered provider" do
    provider = RecordingVfsProvider.new
    registry = Commander::VirtualFS::Registry.new.register(provider)
    path = Commander::VirtualFS::VirtualPath.parse("sftp://example.com/source")
    target = Commander::VirtualFS::VirtualPath.parse("sftp://example.com/target")

    registry.dispatch(Commander::VirtualFS::Request.new(Commander::VirtualFS::Operation::Stat, path)).ok.should be_true
    registry.dispatch(Commander::VirtualFS::Request.new(Commander::VirtualFS::Operation::List, path)).ok.should be_true
    registry.dispatch(Commander::VirtualFS::Request.new(Commander::VirtualFS::Operation::Read, path)).ok.should be_true
    registry.dispatch(Commander::VirtualFS::Request.new(Commander::VirtualFS::Operation::Write, path), Bytes[1, 2, 3]).ok.should be_true
    registry.dispatch(Commander::VirtualFS::Request.new(Commander::VirtualFS::Operation::Mkdir, path)).ok.should be_true
    registry.dispatch(Commander::VirtualFS::Request.new(Commander::VirtualFS::Operation::Delete, path)).ok.should be_true
    registry.dispatch(Commander::VirtualFS::Request.new(Commander::VirtualFS::Operation::Rename, path, target)).ok.should be_true
    registry.dispatch(Commander::VirtualFS::Request.new(Commander::VirtualFS::Operation::Copy, path, target)).ok.should be_true
    registry.dispatch(Commander::VirtualFS::Request.new(Commander::VirtualFS::Operation::OpenStream, path)).ok.should be_true

    provider.calls.should eq([
      Commander::VirtualFS::Operation::Stat,
      Commander::VirtualFS::Operation::List,
      Commander::VirtualFS::Operation::Read,
      Commander::VirtualFS::Operation::Write,
      Commander::VirtualFS::Operation::Mkdir,
      Commander::VirtualFS::Operation::Delete,
      Commander::VirtualFS::Operation::Rename,
      Commander::VirtualFS::Operation::Copy,
      Commander::VirtualFS::Operation::OpenStream,
    ])
  end

  it "raises a typed VFS exception before I/O for unknown schemes" do
    registry = Commander::VirtualFS::Registry.new
    path = Commander::VirtualFS::VirtualPath.new("ftp", "example.com", "/path")

    error = expect_raises(Commander::VirtualFS::VfsException) do
      registry.dispatch(Commander::VirtualFS::Request.new(Commander::VirtualFS::Operation::List, path))
    end
    error.vfs_error.code.should eq(Commander::VirtualFS::ErrorCode::UnsupportedScheme)
  end
end

describe Commander::VirtualFS::UriResolver do
  it "resolves relative and parent segments inside the current scheme" do
    current = Commander::VirtualFS::VirtualPath.parse("sftp://user@example.com/home/user/project")

    child = Commander::VirtualFS::UriResolver.resolve(current, "src/../docs")
    child.scheme.should eq("sftp")
    child.authority.should eq("user@example.com")
    child.path.should eq("/home/user/project/docs")
    child.to_uri.should eq("sftp://user@example.com/home/user/project/docs")

    parent = Commander::VirtualFS::UriResolver.parent(child)
    parent.to_uri.should eq("sftp://user@example.com/home/user/project")
  end

  it "keeps absolute paths on the current remote authority" do
    current = Commander::VirtualFS::VirtualPath.parse("ssh://host.example.org/etc/nginx")
    resolved = Commander::VirtualFS::UriResolver.resolve(current, "/var/log/../tmp")

    resolved.scheme.should eq("ssh")
    resolved.authority.should eq("host.example.org")
    resolved.path.should eq("/var/tmp")
  end

  it "resolves home shortcuts to local file URIs" do
    current = Commander::VirtualFS::VirtualPath.parse("s3://bucket/prefix")
    resolved = Commander::VirtualFS::UriResolver.resolve(current, "~/work", "/Users/example")

    resolved.scheme.should eq("file")
    resolved.authority.should be_nil
    resolved.path.should eq("/Users/example/work")
    resolved.to_uri.should eq("file:///Users/example/work")
  end
end

describe Commander::VirtualFS::FileProvider do
  it "lists and reads local file URIs without network dependencies" do
    root = File.join(Dir.tempdir, "commander-vfs-#{Process.pid}-#{Time.utc.to_unix_ms}")
    file_path = File.join(root, "item.txt")
    binary_path = File.join(root, "binary.dat")
    Dir.mkdir(root)
    File.write(file_path, "hello")
    File.open(binary_path, "w") { |file| file.write(Bytes[0, 255, 65]) }

    begin
      provider = Commander::VirtualFS::FileProvider.new
      list = provider.list(Commander::VirtualFS::VirtualPath.parse(root))
      list.ok.should be_true
      list.entries.map(&.name).should contain("item.txt")
      list.entries.map(&.name).should contain("binary.dat")

      read = provider.read(Commander::VirtualFS::VirtualPath.parse(file_path))
      read.ok.should be_true
      String.new(read.data.not_nil!).should eq("hello")

      binary = provider.read(Commander::VirtualFS::VirtualPath.parse(binary_path))
      binary.ok.should be_true
      binary.data.not_nil!.to_a.should eq([0_u8, 255_u8, 65_u8])
    ensure
      File.delete(file_path) if File.exists?(file_path)
      File.delete(binary_path) if File.exists?(binary_path)
      Dir.delete(root) if Dir.exists?(root)
    end
  end

  it "writes, copies, renames, and deletes local paths through provider operations" do
    root = File.join(Dir.tempdir, "commander-vfs-ops-#{Process.pid}-#{Time.utc.to_unix_ms}")
    Dir.mkdir(root)

    begin
      provider = Commander::VirtualFS::FileProvider.new
      source = Commander::VirtualFS::VirtualPath.parse(File.join(root, "source.txt"))
      copy = Commander::VirtualFS::VirtualPath.parse(File.join(root, "copy.txt"))
      renamed = Commander::VirtualFS::VirtualPath.parse(File.join(root, "renamed.txt"))
      subdir = Commander::VirtualFS::VirtualPath.parse(File.join(root, "subdir"))

      provider.write(source, Bytes[65, 66]).ok.should be_true
      File.read(source.path).should eq("AB")

      provider.copy(source, copy).ok.should be_true
      File.read(copy.path).should eq("AB")

      provider.rename(copy, renamed).ok.should be_true
      File.exists?(renamed.path).should be_true

      provider.mkdir(subdir).ok.should be_true
      Dir.exists?(subdir.path).should be_true

      provider.delete(renamed).ok.should be_true
      File.exists?(renamed.path).should be_false
    ensure
      File.delete(File.join(root, "source.txt")) if File.exists?(File.join(root, "source.txt"))
      File.delete(File.join(root, "copy.txt")) if File.exists?(File.join(root, "copy.txt"))
      File.delete(File.join(root, "renamed.txt")) if File.exists?(File.join(root, "renamed.txt"))
      Dir.delete(File.join(root, "subdir")) if Dir.exists?(File.join(root, "subdir"))
      Dir.delete(root) if Dir.exists?(root)
    end
  end
end

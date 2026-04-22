module Commander
  module VirtualFS
    SUPPORTED_SCHEMES = Set{"file", "ssh", "sftp", "s3"}

    enum EntryKind
      File
      Directory
      Symlink
      Other
    end

    enum Operation
      Stat
      List
      Read
      Write
      Mkdir
      Delete
      Rename
      Copy
      OpenStream
    end

    enum ErrorCode
      NotFound
      PermissionDenied
      AuthFailed
      NetworkError
      Offline
      UnsupportedOperation
      QuotaExceeded
      UnsupportedScheme
    end

    struct VfsError
      getter code : ErrorCode
      getter message : String

      def initialize(@code : ErrorCode, @message : String)
      end
    end

    class VfsException < Exception
      getter vfs_error : VfsError

      def initialize(@vfs_error : VfsError)
        super(@vfs_error.message)
      end
    end

    struct VirtualPath
      getter scheme : String
      getter authority : String?
      getter path : String

      def initialize(@scheme : String, @authority : String?, @path : String)
      end

      def self.parse(value : String) : VirtualPath
        if value.includes?("://")
          scheme, rest = value.split("://", 2)
          unless SUPPORTED_SCHEMES.includes?(scheme)
            raise VfsException.new(VfsError.new(ErrorCode::UnsupportedScheme, "unsupported VFS scheme: #{scheme}"))
          end

          authority, path = split_authority_path(rest)
          authority_value = authority.empty? ? nil : authority
          return new(scheme, authority_value, path)
        end

        new("file", nil, File.expand_path(value))
      end

      private def self.split_authority_path(rest : String) : Tuple(String, String)
        slash = rest.index("/")
        return {rest, "/"} unless slash

        {rest[0, slash], rest[slash..]}
      end

      def local? : Bool
        @scheme == "file"
      end

      def remote? : Bool
        !local?
      end

      def to_uri : String
        if @scheme == "file"
          "file://#{@path}"
        else
          "#{@scheme}://#{@authority}#{@path}"
        end
      end

      def to_s(io : IO) : Nil
        if @scheme == "file"
          io << @path
        else
          io << @scheme << "://"
          io << @authority if @authority
          io << @path
        end
      end
    end

    struct Entry
      getter name : String
      getter path : VirtualPath
      getter kind : EntryKind
      getter size : Int64?
      getter modified_at : Time?
      getter permissions : UInt32?

      def initialize(@name : String, @path : VirtualPath, @kind : EntryKind, @size : Int64? = nil, @modified_at : Time? = nil, @permissions : UInt32? = nil)
      end
    end

    struct Request
      getter operation : Operation
      getter path : VirtualPath
      getter target : VirtualPath?

      def initialize(@operation : Operation, @path : VirtualPath, @target : VirtualPath? = nil)
      end
    end

    module UriResolver
      def self.resolve(current : VirtualPath, input : String, home : String = ENV["HOME"]? || "/") : VirtualPath
        return current if input.empty?
        return VirtualPath.parse(input) if input.includes?("://")

        if input == "~" || input.starts_with?("~/")
          suffix = input == "~" ? "" : input[2..]
          return VirtualPath.new("file", nil, normalize_path(File.join(home, suffix)))
        end

        if input.starts_with?("/")
          return VirtualPath.new(current.scheme, current.authority, normalize_path(input))
        end

        append(current, input)
      end

      def self.append(current : VirtualPath, segment : String) : VirtualPath
        base = current.path
        joined = base.ends_with?("/") ? "#{base}#{segment}" : "#{base}/#{segment}"
        VirtualPath.new(current.scheme, current.authority, normalize_path(joined))
      end

      def self.parent(current : VirtualPath) : VirtualPath
        normalized = normalize_path(current.path)
        parent = File.dirname(normalized)
        parent = "/" if parent == "."
        VirtualPath.new(current.scheme, current.authority, parent)
      end

      def self.normalize_path(path : String) : String
        absolute = path.starts_with?("/")
        parts = [] of String
        path.split("/").each do |part|
          next if part.empty? || part == "."
          if part == ".."
            parts.pop?
          else
            parts << part
          end
        end

        prefix = absolute ? "/" : ""
        normalized = "#{prefix}#{parts.join("/")}"
        normalized.empty? ? "/" : normalized
      end
    end

    struct Response
      getter ok : Bool
      getter entries : Array(Entry)
      getter data : Bytes?
      getter error : VfsError?

      def initialize(@ok : Bool, @entries : Array(Entry) = [] of Entry, @data : Bytes? = nil, @error : VfsError? = nil)
      end

      def self.failure(code : ErrorCode, message : String) : Response
        new(false, error: VfsError.new(code, message))
      end
    end

    abstract class Provider
      abstract def scheme : String
      abstract def stat(path : VirtualPath) : Response
      abstract def list(path : VirtualPath) : Response
      abstract def read(path : VirtualPath) : Response
      abstract def write(path : VirtualPath, data : Bytes) : Response
      abstract def mkdir(path : VirtualPath) : Response
      abstract def delete(path : VirtualPath) : Response
      abstract def rename(path : VirtualPath, target : VirtualPath) : Response
      abstract def copy(path : VirtualPath, target : VirtualPath) : Response
      abstract def open_stream(path : VirtualPath) : Response
    end

    class Registry
      def self.default : Registry
        registry = new.register(FileProvider.new)
        SUPPORTED_SCHEMES.each do |scheme|
          next if scheme == "file"

          registry.register(UnavailableRemoteProvider.new(scheme))
        end
        registry
      end

      def initialize
        @providers = {} of String => Provider
      end

      def register(provider : Provider) : Registry
        @providers[provider.scheme] = provider
        self
      end

      def provider_for(path : VirtualPath) : Provider
        provider = @providers[path.scheme]?
        return provider if provider

        raise VfsException.new(VfsError.new(ErrorCode::UnsupportedScheme, "unsupported VFS scheme: #{path.scheme}"))
      end

      def dispatch(request : Request, data : Bytes? = nil) : Response
        provider = provider_for(request.path)

        case request.operation
        in Operation::Stat
          provider.stat(request.path)
        in Operation::List
          provider.list(request.path)
        in Operation::Read
          provider.read(request.path)
        in Operation::Write
          provider.write(request.path, data || Bytes.empty)
        in Operation::Mkdir
          provider.mkdir(request.path)
        in Operation::Delete
          provider.delete(request.path)
        in Operation::Rename
          target = request.target
          return Response.failure(ErrorCode::UnsupportedOperation, "rename requires a target URI") unless target

          provider.rename(request.path, target)
        in Operation::Copy
          target = request.target
          return Response.failure(ErrorCode::UnsupportedOperation, "copy requires a target URI") unless target

          provider.copy(request.path, target)
        in Operation::OpenStream
          provider.open_stream(request.path)
        end
      end
    end

    class UnavailableRemoteProvider < Provider
      getter scheme : String

      def initialize(@scheme : String)
        unless SUPPORTED_SCHEMES.includes?(@scheme) && @scheme != "file"
          raise ArgumentError.new("unsupported remote VFS scheme: #{@scheme}")
        end
      end

      def stat(path : VirtualPath) : Response
        unavailable("stat")
      end

      def list(path : VirtualPath) : Response
        unavailable("list")
      end

      def read(path : VirtualPath) : Response
        unavailable("read")
      end

      def write(path : VirtualPath, data : Bytes) : Response
        unavailable("write")
      end

      def mkdir(path : VirtualPath) : Response
        unavailable("mkdir")
      end

      def delete(path : VirtualPath) : Response
        unavailable("delete")
      end

      def rename(path : VirtualPath, target : VirtualPath) : Response
        unavailable("rename")
      end

      def copy(path : VirtualPath, target : VirtualPath) : Response
        unavailable("copy")
      end

      def open_stream(path : VirtualPath) : Response
        unavailable("open_stream")
      end

      private def unavailable(operation : String) : Response
        Response.failure(ErrorCode::UnsupportedOperation, "#{@scheme} #{operation} provider is not configured")
      end
    end

    class MemoryProvider < Provider
      getter scheme : String

      def initialize(@scheme : String = "sftp", @offline : Bool = false)
        raise ArgumentError.new("unsupported memory VFS scheme: #{@scheme}") unless SUPPORTED_SCHEMES.includes?(@scheme)

        @entries = {} of String => Entry
        @data = {} of String => Bytes
      end

      def offline=(@offline : Bool)
      end

      def add_directory(path : VirtualPath) : MemoryProvider
        @entries[key(path)] = Entry.new(File.basename(path.path), path, EntryKind::Directory)
        self
      end

      def add_file(path : VirtualPath, data : Bytes) : MemoryProvider
        @entries[key(path)] = Entry.new(File.basename(path.path), path, EntryKind::File, data.size.to_i64)
        @data[key(path)] = copy_bytes(data)
        self
      end

      def stat(path : VirtualPath) : Response
        entry = @entries[key(path)]?
        return Response.failure(ErrorCode::NotFound, "memory path not found: #{path.to_uri}") unless entry

        Response.new(true, [entry])
      end

      def list(path : VirtualPath) : Response
        return offline_list(path) if @offline

        prefix = normalized_directory(path.path)
        entries = @entries.values.select do |entry|
          entry.path.authority == path.authority && File.dirname(entry.path.path) == prefix
        end.sort_by(&.name)
        Response.new(true, entries)
      end

      def read(path : VirtualPath) : Response
        data = @data[key(path)]?
        return Response.failure(ErrorCode::NotFound, "memory file not found: #{path.to_uri}") unless data

        Response.new(true, data: copy_bytes(data))
      end

      def write(path : VirtualPath, data : Bytes) : Response
        return offline_mutation("write") if @offline

        add_file(path, data)
        Response.new(true)
      end

      def mkdir(path : VirtualPath) : Response
        return offline_mutation("mkdir") if @offline

        add_directory(path)
        Response.new(true)
      end

      def delete(path : VirtualPath) : Response
        return offline_mutation("delete") if @offline

        @entries.delete(key(path))
        @data.delete(key(path))
        Response.new(true)
      end

      def rename(path : VirtualPath, target : VirtualPath) : Response
        return offline_mutation("rename") if @offline

        entry = @entries.delete(key(path))
        return Response.failure(ErrorCode::NotFound, "memory path not found: #{path.to_uri}") unless entry

        data = @data.delete(key(path))
        moved = Entry.new(File.basename(target.path), target, entry.kind, entry.size, entry.modified_at, entry.permissions)
        @entries[key(target)] = moved
        @data[key(target)] = data if data
        Response.new(true)
      end

      def copy(path : VirtualPath, target : VirtualPath) : Response
        return offline_mutation("copy") if @offline

        entry = @entries[key(path)]?
        return Response.failure(ErrorCode::NotFound, "memory path not found: #{path.to_uri}") unless entry

        data = @data[key(path)]?
        copied = Entry.new(File.basename(target.path), target, entry.kind, entry.size, entry.modified_at, entry.permissions)
        @entries[key(target)] = copied
        @data[key(target)] = copy_bytes(data) if data
        Response.new(true)
      end

      def open_stream(path : VirtualPath) : Response
        Response.failure(ErrorCode::UnsupportedOperation, "memory stream handles are not exposed through Response")
      end

      private def offline_list(path : VirtualPath) : Response
        entries = list_without_offline(path)
        Response.new(true, entries)
      end

      private def list_without_offline(path : VirtualPath) : Array(Entry)
        prefix = normalized_directory(path.path)
        @entries.values.select do |entry|
          entry.path.authority == path.authority && File.dirname(entry.path.path) == prefix
        end.sort_by(&.name)
      end

      private def offline_mutation(operation : String) : Response
        Response.failure(ErrorCode::Offline, "memory #{operation} is unavailable while offline")
      end

      private def normalized_directory(path : String) : String
        normalized = UriResolver.normalize_path(path)
        normalized.empty? ? "/" : normalized
      end

      private def key(path : VirtualPath) : String
        "#{path.scheme}://#{path.authority}#{UriResolver.normalize_path(path.path)}"
      end

      private def copy_bytes(data : Bytes) : Bytes
        copy = Bytes.new(data.size)
        copy.copy_from(data)
        copy
      end
    end

    class FileProvider < Provider
      def scheme : String
        "file"
      end

      def stat(path : VirtualPath) : Response
        local = local_path(path)
        return Response.failure(ErrorCode::NotFound, "file not found: #{local}") unless File.exists?(local) || Dir.exists?(local)

        Response.new(true, [entry_for(local)])
      rescue ex
        Response.failure(ErrorCode::PermissionDenied, ex.message || "file stat failed")
      end

      def list(path : VirtualPath) : Response
        local = local_path(path)
        return Response.failure(ErrorCode::NotFound, "directory not found: #{local}") unless Dir.exists?(local)

        entries = Dir.children(local).sort.map do |name|
          entry_for(File.join(local, name))
        end
        Response.new(true, entries)
      rescue ex
        Response.failure(ErrorCode::PermissionDenied, ex.message || "file list failed")
      end

      def read(path : VirtualPath) : Response
        local = local_path(path)
        bytes = Bytes.new(File.info(local).size.to_i)
        File.open(local) { |file| file.read_fully(bytes) }
        Response.new(true, data: bytes)
      rescue ex
        Response.failure(ErrorCode::NotFound, ex.message || "file read failed")
      end

      def write(path : VirtualPath, data : Bytes) : Response
        File.open(local_path(path), "w") { |file| file.write(data) }
        Response.new(true)
      rescue ex
        Response.failure(ErrorCode::PermissionDenied, ex.message || "file write failed")
      end

      def mkdir(path : VirtualPath) : Response
        Dir.mkdir_p(local_path(path))
        Response.new(true)
      rescue ex
        Response.failure(ErrorCode::PermissionDenied, ex.message || "mkdir failed")
      end

      def delete(path : VirtualPath) : Response
        local = local_path(path)
        if Dir.exists?(local)
          Dir.delete(local)
        else
          File.delete(local)
        end
        Response.new(true)
      rescue ex
        Response.failure(ErrorCode::PermissionDenied, ex.message || "delete failed")
      end

      def rename(path : VirtualPath, target : VirtualPath) : Response
        File.rename(local_path(path), local_path(target))
        Response.new(true)
      rescue ex
        Response.failure(ErrorCode::PermissionDenied, ex.message || "rename failed")
      end

      def copy(path : VirtualPath, target : VirtualPath) : Response
        File.copy(local_path(path), local_path(target))
        Response.new(true)
      rescue ex
        Response.failure(ErrorCode::PermissionDenied, ex.message || "copy failed")
      end

      def open_stream(path : VirtualPath) : Response
        Response.failure(ErrorCode::UnsupportedOperation, "stream handles are not exposed through Response")
      end

      private def local_path(path : VirtualPath) : String
        raise VfsException.new(VfsError.new(ErrorCode::UnsupportedScheme, "expected file URI")) unless path.scheme == "file"

        path.path
      end

      private def entry_for(local : String) : Entry
        info = File.info(local)
        kind = if info.directory?
                 EntryKind::Directory
               elsif info.file?
                 EntryKind::File
               else
                 EntryKind::Other
               end

        Entry.new(
          name: File.basename(local),
          path: VirtualPath.new("file", nil, local),
          kind: kind,
          size: info.size,
          modified_at: info.modification_time,
          permissions: info.permissions.value.to_u32
        )
      end
    end
  end
end

require "uri"

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

    struct VirtualPath
      getter scheme : String
      getter authority : String?
      getter path : String

      def initialize(@scheme : String, @authority : String?, @path : String)
      end

      def self.parse(value : String) : VirtualPath
        if value.includes?("://")
          uri = URI.parse(value)
          scheme = uri.scheme || "file"
          raise ArgumentError.new("unsupported VFS scheme: #{scheme}") unless SUPPORTED_SCHEMES.includes?(scheme)

          path = uri.path.empty? ? "/" : uri.path
          return new(scheme, uri.host, path) unless scheme == "s3"

          bucket = uri.host
          key = uri.path.empty? ? "/" : uri.path
          return new(scheme, bucket, key)
        end

        new("file", nil, File.expand_path(value))
      end

      def local? : Bool
        @scheme == "file"
      end

      def remote? : Bool
        !local?
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

      def initialize(@name : String, @path : VirtualPath, @kind : EntryKind, @size : Int64? = nil, @modified_at : Time? = nil)
      end
    end

    struct Request
      getter operation : Operation
      getter path : VirtualPath
      getter target : VirtualPath?

      def initialize(@operation : Operation, @path : VirtualPath, @target : VirtualPath? = nil)
      end
    end

    struct Response
      getter ok : Bool
      getter entries : Array(Entry)
      getter error : String?

      def initialize(@ok : Bool, @entries : Array(Entry) = [] of Entry, @error : String? = nil)
      end
    end

    abstract class Provider
      abstract def scheme : String
      abstract def stat(path : VirtualPath) : Response
      abstract def list(path : VirtualPath) : Response
    end
  end
end

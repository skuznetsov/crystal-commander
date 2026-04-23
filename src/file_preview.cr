require "./snapshots"

module Commander
  class FilePreview
    MAX_BYTES = 32 * 1024

    def self.load(path : String, max_bytes : Int32 = MAX_BYTES) : PreviewSnapshot
      unless File.file?(path)
        return PreviewSnapshot.new(path, File.basename(path), "", false, "not a regular file")
      end

      max_bytes = MAX_BYTES if max_bytes < 1
      bytes = File.open(path) do |file|
        buffer = Bytes.new(max_bytes + 1)
        read_count = file.read(buffer)
        String.new(buffer[0, read_count])
      end
      truncated = bytes.bytesize > max_bytes
      content = truncated ? bytes.byte_slice(0, max_bytes) : bytes

      if content.includes?('\0')
        return PreviewSnapshot.new(path, File.basename(path), "", truncated, "binary file preview is not supported")
      end

      PreviewSnapshot.new(path, File.basename(path), content, truncated, nil)
    rescue ex : File::Error
      PreviewSnapshot.new(path, File.basename(path), "", false, ex.message)
    end
  end
end

require "./snapshots"

module Commander
  enum FileOperationKind
    View
    Edit
    Copy
    RenameMove
    Mkdir
    Delete
  end

  struct FileOperationPlan
    getter kind : FileOperationKind
    getter source_panel : Int32
    getter target_panel : Int32?
    getter sources : Array(String)
    getter target_directory : String?

    def initialize(@kind : FileOperationKind, @source_panel : Int32, @target_panel : Int32?, @sources : Array(String), @target_directory : String?)
    end

    def empty? : Bool
      @sources.empty?
    end

    def summary : String
      target = @target_directory
      case @kind
      when FileOperationKind::View
        "View #{@sources.first? || "(none)"}"
      when FileOperationKind::Edit
        "Edit #{@sources.first? || "(none)"}"
      when FileOperationKind::Copy
        "Copy #{@sources.size} item(s) to #{target || "(none)"}"
      when FileOperationKind::RenameMove
        "RenMov #{@sources.size} item(s) to #{target || "(none)"}"
      when FileOperationKind::Mkdir
        "Mkdir in #{target || "(none)"}"
      when FileOperationKind::Delete
        "Delete #{@sources.size} item(s)"
      else
        "#{@kind} #{@sources.size} item(s)"
      end
    end

    def to_snapshot : OperationPlanSnapshot
      OperationPlanSnapshot.new(
        kind: @kind.to_s,
        source_panel: @source_panel,
        target_panel: @target_panel,
        sources: @sources,
        target_directory: @target_directory,
        summary: summary
      )
    end
  end

  struct FileOperationResult
    getter ok : Bool
    getter message : String
    getter path : String?

    def initialize(@ok : Bool, @message : String, @path : String? = nil)
    end
  end

  class FileOperations
    def self.mkdir(path : String) : FileOperationResult
      expanded = File.expand_path(path)
      if File.exists?(expanded)
        return FileOperationResult.new(false, "Path already exists", expanded)
      end

      Dir.mkdir_p(expanded)
      FileOperationResult.new(true, "Directory created", expanded)
    rescue ex : File::Error
      FileOperationResult.new(false, ex.message || ex.class.name, expanded)
    end

    def self.copy_file(source : String, target_directory : String) : FileOperationResult
      expanded_source = File.expand_path(source)
      expanded_target_directory = File.expand_path(target_directory)

      unless File.file?(expanded_source)
        return FileOperationResult.new(false, "Source is not a regular file", expanded_source)
      end

      unless Dir.exists?(expanded_target_directory)
        return FileOperationResult.new(false, "Target directory does not exist", expanded_target_directory)
      end

      target = File.join(expanded_target_directory, File.basename(expanded_source))
      if File.exists?(target)
        return FileOperationResult.new(false, "Target already exists", target)
      end

      File.copy(expanded_source, target)
      FileOperationResult.new(true, "Copied", target)
    rescue ex : File::Error
      FileOperationResult.new(false, ex.message || ex.class.name, nil)
    end
  end
end

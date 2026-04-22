require "./plugin_manifest"
require "./command_registry"
require "./keymap"
require "./virtual_fs"

module Commander
  struct LoadedPlugin
    getter manifest : PluginManifest
    getter directory : String

    def initialize(@manifest : PluginManifest, @directory : String)
    end

    def entrypoint_path : String?
      entrypoint = @manifest.entrypoint
      return nil unless entrypoint

      File.expand_path(File.join(@directory, entrypoint))
    end
  end

  class PluginHost
    SUPPORTED_RUNTIMES = Set{"lua", "subprocess"}
    SUPPORTED_PERMISSIONS = Set{
      "filesystem.read",
      "filesystem.write",
      "process.spawn",
      "network",
      "ui.status",
      "panel.read",
      "panel.virtual",
    }

    getter root : String
    getter manifests : Array(PluginManifest)
    getter loaded_plugins : Array(LoadedPlugin)
    getter load_errors : Array(String)

    def initialize(@root : String = "plugins")
      @manifests = [] of PluginManifest
      @loaded_plugins = [] of LoadedPlugin
      @load_errors = [] of String
    end

    def load_manifests : Nil
      @manifests.clear
      @loaded_plugins.clear
      @load_errors.clear

      return unless Dir.exists?(@root)

      Dir.each_child(@root) do |child|
        manifest_path = File.join(@root, child, "plugin.json")
        next unless File.file?(manifest_path)

        load_manifest(manifest_path, File.join(@root, child))
      end

      validate_command_ids
    end

    def commands : Array(PluginCommandManifest)
      @manifests.flat_map(&.commands)
    end

    def key_bindings : Array(PluginKeyBindingManifest)
      @manifests.flat_map(&.key_bindings)
    end

    def to_snapshots : Array(PluginSnapshot)
      @loaded_plugins.map do |plugin|
        plugin.manifest.to_snapshot(plugin.entrypoint_path)
      end
    end

    def loaded_plugin_for_command(command_id : String) : LoadedPlugin?
      @loaded_plugins.find do |plugin|
        plugin.manifest.commands.any? { |command| command.id == command_id }
      end
    end

    def register_placeholder_commands(registry : CommandRegistry, &handler : LoadedPlugin, PluginCommandManifest -> Nil) : Nil
      @loaded_plugins.each do |plugin|
        plugin.manifest.commands.each do |command|
          next if registry.registered?(command.id)

          registry.register(command.id, command.title, command.description, plugin_id: plugin.manifest.id) do |_ctx|
            handler.call(plugin, command)
          end
        end
      end
    end

    private def load_manifest(path : String, directory : String) : Nil
      manifest = PluginManifest.from_json(File.read(path))
      @manifests << manifest
      @loaded_plugins << LoadedPlugin.new(manifest, File.expand_path(directory))
    rescue ex : JSON::ParseException
      @load_errors << "#{path}: #{ex.message}"
    rescue ex : File::Error
      @load_errors << "#{path}: #{ex.message}"
    end

    private def validate_command_ids : Nil
      seen = {} of String => String

      @manifests.each do |manifest|
        unless SUPPORTED_RUNTIMES.includes?(manifest.runtime)
          @load_errors << "#{manifest.id}: unsupported runtime #{manifest.runtime}"
        end

        manifest.permissions.each do |permission|
          unless supported_permission?(permission)
            @load_errors << "#{manifest.id}: unsupported permission #{permission}"
          end
        end

        loaded = @loaded_plugins.find { |item| item.manifest.id == manifest.id }
        entrypoint_path = loaded.try(&.entrypoint_path)
        if manifest.entrypoint && entrypoint_path && !File.file?(entrypoint_path)
          @load_errors << "#{manifest.id}: entrypoint not found #{entrypoint_path}"
        end

        manifest.commands.each do |command|
          owner = seen[command.id]?
          if owner
            @load_errors << "#{manifest.id}: duplicate command id #{command.id} already declared by #{owner}"
          else
            seen[command.id] = manifest.id
          end
        end

        manifest.key_bindings.each do |binding|
          unless Keymap.parse_spec(binding.key)
            @load_errors << "#{manifest.id}: unsupported key binding #{binding.key}"
            next
          end

          next if manifest.commands.any? { |command| command.id == binding.command }
          @load_errors << "#{manifest.id}: key binding references undeclared command #{binding.command}"
        end
      end
    end

    private def supported_permission?(permission : String) : Bool
      return true if SUPPORTED_PERMISSIONS.includes?(permission)
      return false unless permission.starts_with?("vfs.read:")

      scheme = permission.split(":", 2)[1]
      scheme == "*" || VirtualFS::SUPPORTED_SCHEMES.includes?(scheme)
    end
  end
end

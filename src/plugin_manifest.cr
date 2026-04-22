require "json"
require "./snapshots"

module Commander
  struct PluginCommandManifest
    include JSON::Serializable

    getter id : String
    getter title : String
    getter description : String

    def initialize(@id : String, @title : String, @description : String = "")
    end
  end

  struct PluginKeyBindingManifest
    include JSON::Serializable

    getter key : String
    getter command : String

    def initialize(@key : String, @command : String)
    end
  end

  struct PluginManifest
    include JSON::Serializable

    getter id : String
    getter name : String
    getter version : String
    getter api_version : String
    getter runtime : String
    getter entrypoint : String?
    getter permissions : Array(String)
    getter commands : Array(PluginCommandManifest)
    getter key_bindings : Array(PluginKeyBindingManifest)

    def initialize(
      @id : String,
      @name : String,
      @version : String,
      @runtime : String,
      @api_version : String = "0.1",
      @entrypoint : String? = nil,
      @permissions : Array(String) = [] of String,
      @commands : Array(PluginCommandManifest) = [] of PluginCommandManifest,
      @key_bindings : Array(PluginKeyBindingManifest) = [] of PluginKeyBindingManifest
    )
    end

    def to_snapshot(entrypoint_path : String? = nil) : PluginSnapshot
      PluginSnapshot.new(
        id: @id,
        name: @name,
        version: @version,
        api_version: @api_version,
        runtime: @runtime,
        entrypoint: @entrypoint,
        entrypoint_path: entrypoint_path,
        permissions: @permissions,
        command_ids: @commands.map(&.id),
        key_bindings: @key_bindings.map { |binding| "#{binding.key} -> #{binding.command}" }
      )
    end
  end
end

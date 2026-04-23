require "socket"
require "./automation_protocol"

module Commander
  class AutomationServer
    getter socket_path : String

    @server : UNIXServer?
    @running : Bool
    @created_socket : Bool

    def initialize(@socket_path : String)
      @server = nil
      @running = false
      @created_socket = false
    end

    def enabled? : Bool
      !@socket_path.empty?
    end

    def start(snapshot_provider : -> AppSnapshot, policy : AutomationCommand -> Bool, &executor : AutomationCommand -> AutomationResponse) : Nil
      return if @running
      raise "automation socket path is empty" if @socket_path.empty?
      raise "automation socket path already exists: #{@socket_path}" if File.exists?(@socket_path)

      @server = UNIXServer.new(@socket_path)
      @created_socket = true
      @running = true

      spawn(name: "commander-automation-server") do
        accept_loop(snapshot_provider, policy, executor)
      end
    end

    def start(snapshot_provider : -> AppSnapshot, &executor : AutomationCommand -> AutomationResponse) : Nil
      start(snapshot_provider, ->(command : AutomationCommand) { AutomationPolicy.ipc_allowed?(command) }) do |command|
        executor.call(command)
      end
    end

    def start(&executor : AutomationCommand -> AutomationResponse) : Nil
      start(-> { default_snapshot }) { |command| executor.call(command) }
    end

    def stop : Nil
      @running = false
      @server.try(&.close) rescue nil
      @server = nil
      if @created_socket && File.exists?(@socket_path)
        File.delete(@socket_path) rescue nil
      end
      @created_socket = false
    end

    def handle_command(command : AutomationCommand, policy : AutomationCommand -> Bool, &executor : AutomationCommand -> AutomationResponse) : AutomationResponse
      unless policy.call(command)
        return AutomationResponse.error(AutomationPolicy.ipc_denial(command))
      end

      yield command
    end

    def handle_command(command : AutomationCommand, &executor : AutomationCommand -> AutomationResponse) : AutomationResponse
      handle_command(command, ->(candidate : AutomationCommand) { AutomationPolicy.ipc_allowed?(candidate) }, &executor)
    end

    def handle_request(request : AutomationRequest, snapshot_provider : -> AppSnapshot, policy : AutomationCommand -> Bool, &executor : AutomationCommand -> AutomationResponse) : AutomationResponse
      case request.kind
      when "command"
        command = request.command
        return AutomationResponse.error("automation command request requires command") unless command

        handle_command(command, policy, &executor)
      when "snapshot", "state", "status"
        AutomationResponse.snapshot(snapshot_provider.call)
      else
        AutomationResponse.error("unknown automation request kind: #{request.kind}")
      end
    end

    def handle_request(request : AutomationRequest, snapshot_provider : -> AppSnapshot, &executor : AutomationCommand -> AutomationResponse) : AutomationResponse
      handle_request(request, snapshot_provider, ->(command : AutomationCommand) { AutomationPolicy.ipc_allowed?(command) }, &executor)
    end

    private def accept_loop(snapshot_provider : -> AppSnapshot, policy : AutomationCommand -> Bool, executor : AutomationCommand -> AutomationResponse) : Nil
      while @running
        client = @server.try(&.accept?)
        next unless client

        accepted = client.not_nil!
        spawn(name: "commander-automation-client") do
          handle_client(accepted, snapshot_provider, policy, executor)
        end
      end
    rescue IO::Error
      # Closing the server during shutdown interrupts accept.
    end

    private def handle_client(client : UNIXSocket, snapshot_provider : -> AppSnapshot, policy : AutomationCommand -> Bool, executor : AutomationCommand -> AutomationResponse) : Nil
      line = client.gets
      if line
        client.puts(handle_line(line, snapshot_provider, policy, executor))
      else
        client.puts(error_json("empty automation request"))
      end
    rescue ex : JSON::ParseException | JSON::SerializableError
      client.puts(error_json(ex.message || "invalid automation request")) rescue nil
    rescue ex
      client.puts(error_json(ex.message || ex.class.name)) rescue nil
    ensure
      client.close rescue nil
    end

    private def handle_line(line : String, snapshot_provider : -> AppSnapshot, policy : AutomationCommand -> Bool, executor : AutomationCommand -> AutomationResponse) : String
      parsed = JSON.parse(line)
      if parsed.as_h.has_key?("kind")
        request = AutomationRequest.from_json(line)
        handle_request(request, snapshot_provider, policy, &executor).to_json
      else
        command = AutomationCommand.from_json(line)
        handle_command(command, policy, &executor).to_json
      end
    end

    private def error_json(message : String) : String
      {"ok" => false, "status_text" => "Automation IPC request failed", "error" => message}.to_json
    end

    private def default_snapshot : AppSnapshot
      AppSnapshot.new(
        active_panel: 0,
        panel_count: 0,
        running: true,
        status_text: "Automation server running",
        dry_run: false,
        plugin_root: "",
        plugins: [] of PluginSnapshot,
        plugin_runtimes: [] of PluginRuntimeSnapshot,
        plugin_errors: [] of String,
        commands: [] of CommandSnapshot,
        pending_operation: nil,
        preview: nil,
        external_view: nil,
        viewer_sessions: [] of ViewerSessionSnapshot,
        panels: [] of PanelSnapshot
      )
    end
  end
end

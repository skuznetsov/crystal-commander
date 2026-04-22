require "./automation_protocol"

module Commander
  class AutomationServer
    getter socket_path : String

    def initialize(@socket_path : String)
    end

    def enabled? : Bool
      !@socket_path.empty?
    end

    def start : Nil
      # Stateful IPC is not implemented yet.
      # This class exists to keep protocol ownership explicit before socket code is added.
    end

    def stop : Nil
    end

    def handle_command(command : AutomationCommand, &executor : AutomationCommand -> AutomationResponse) : AutomationResponse
      yield command
    end
  end
end

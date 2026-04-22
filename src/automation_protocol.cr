require "json"
require "./snapshots"

module Commander
  struct AutomationCommand
    include JSON::Serializable

    getter command_id : String
    getter panel_index : Int32
    getter argument : String?
    getter dry_run : Bool

    def initialize(@command_id : String, @panel_index : Int32 = 0, @argument : String? = nil, @dry_run : Bool = false)
    end
  end

  struct AutomationResponse
    include JSON::Serializable

    getter ok : Bool
    getter status_text : String
    getter error : String?
    getter snapshot : AppSnapshot

    def initialize(@ok : Bool, @status_text : String, @snapshot : AppSnapshot, @error : String? = nil)
    end
  end
end

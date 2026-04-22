require "./snapshots"

module Commander
  record CommandContext,
    panel_index : Int32,
    argument : String?

  record Command,
    id : String,
    title : String,
    description : String,
    plugin_id : String?,
    handler : Proc(CommandContext, Nil)

  class CommandRegistry
    def initialize
      @commands = {} of String => Command
      @aliases = {} of String => String
    end

    def register(id : String, title : String, description : String = "", plugin_id : String? = nil, &handler : CommandContext -> Nil) : Nil
      @commands[id] = Command.new(id, title, description, plugin_id, handler)
    end

    def execute(id : String, context : CommandContext) : Bool
      command = @commands[resolve(id)]?
      return false unless command

      command.handler.call(context)
      true
    end

    def registered?(id : String) : Bool
      @commands.has_key?(resolve(id))
    end

    def register_alias(alias_id : String, target_id : String) : Nil
      @aliases[alias_id] = target_id
    end

    def each(&block : Command -> Nil) : Nil
      @commands.each_value do |command|
        yield command
      end
    end

    def to_snapshots : Array(CommandSnapshot)
      @commands.values.map do |command|
        CommandSnapshot.new(
          id: command.id,
          title: command.title,
          description: command.description,
          plugin_id: command.plugin_id
        )
      end
    end

    private def resolve(id : String) : String
      @aliases[id]? || id
    end
  end
end

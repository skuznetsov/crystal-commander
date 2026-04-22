module Commander
  KEYMAP_COMMAND_MODIFIERS = (1_u32 << 18) | (1_u32 << 20)
  KEYMAP_MOD_CONTROL = 1_u32 << 18
  KEYMAP_MOD_COMMAND = 1_u32 << 20
  KEYMAP_MOD_SHIFT = 1_u32 << 17
  KEYMAP_MOD_OPTION = 1_u32 << 19

  KEYMAP_NAMED_KEYS = {
    "space" => 49,
    "esc" => 53,
    "escape" => 53,
    "return" => 36,
    "enter" => 36,
    "backspace" => 51,
    "delete" => 51,
    "up" => 126,
    "down" => 125,
    "left" => 123,
    "right" => 124,
    "home" => 115,
    "end" => 119,
    "pageup" => 116,
    "pagedown" => 121,
    "f1" => 122,
    "f2" => 120,
    "f3" => 99,
    "f4" => 118,
    "f5" => 96,
    "f6" => 97,
    "f7" => 98,
    "f8" => 100,
    "f9" => 101,
    "f10" => 109,
    "a" => 0,
    "b" => 11,
    "c" => 8,
    "d" => 2,
    "e" => 14,
    "f" => 3,
    "g" => 5,
    "h" => 4,
    "i" => 34,
    "j" => 38,
    "k" => 40,
    "l" => 37,
    "m" => 46,
    "n" => 45,
    "o" => 31,
    "p" => 35,
    "q" => 12,
    "r" => 15,
    "s" => 1,
    "t" => 17,
    "u" => 32,
    "v" => 9,
    "w" => 13,
    "x" => 7,
    "y" => 16,
    "z" => 6,
  }

  class KeyBinding
    getter key_code : Int32
    getter command_id : String
    getter require_any_modifiers : UInt32

    def initialize(@key_code : Int32, @command_id : String, @require_any_modifiers : UInt32 = 0_u32)
    end

    def matches?(key_code : Int32, modifiers : UInt32) : Bool
      return false unless @key_code == key_code
      return (modifiers & KEYMAP_COMMAND_MODIFIERS) == 0 if @require_any_modifiers == 0_u32

      (modifiers & @require_any_modifiers) != 0
    end
  end

  class Keymap
    def initialize
      @bindings = [] of KeyBinding
    end

    def bind(key_code : Int32, command_id : String, require_any_modifiers : UInt32 = 0_u32) : Nil
      @bindings << KeyBinding.new(key_code, command_id, require_any_modifiers)
    end

    def bind_spec(spec : String, command_id : String) : Bool
      parsed = self.class.parse_spec(spec)
      return false unless parsed

      key_code, modifiers = parsed
      bind(key_code, command_id, modifiers)
      true
    end

    def command_for(key_code : Int32, modifiers : UInt32) : String?
      binding = @bindings.find { |item| item.require_any_modifiers != 0_u32 && item.matches?(key_code, modifiers) }
      binding ||= @bindings.find { |item| item.matches?(key_code, modifiers) }
      binding.try(&.command_id)
    end

    def each(&block : KeyBinding -> Nil) : Nil
      @bindings.each do |binding|
        yield binding
      end
    end

    def self.parse_spec(spec : String) : {Int32, UInt32}?
      parts = spec.downcase.split("-").reject(&.empty?)
      return nil if parts.empty?

      key_name = parts.last
      key_code = KEYMAP_NAMED_KEYS[key_name]?
      return nil unless key_code

      modifiers = 0_u32
      parts[0, parts.size - 1].each do |part|
        case part
        when "ctrl", "control"
          modifiers |= KEYMAP_MOD_CONTROL
        when "cmd", "command", "meta"
          modifiers |= KEYMAP_MOD_COMMAND
        when "shift"
          modifiers |= KEYMAP_MOD_SHIFT
        when "opt", "option", "alt"
          modifiers |= KEYMAP_MOD_OPTION
        else
          return nil
        end
      end

      {key_code.to_i32, modifiers}
    end
  end
end

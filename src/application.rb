CHARS_MAP = [
    0xF0, 0x90, 0x90, 0x90, 0xF0, # 0
    0x20, 0x60, 0x20, 0x20, 0x70, # 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, # 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, # 3
    0x90, 0x90, 0xF0, 0x10, 0x10, # 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, # 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, # 6
    0xF0, 0x10, 0x20, 0x40, 0x40, # 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, # 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, # 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, # A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, # B
    0xF0, 0x80, 0x80, 0x80, 0xF0, # C
    0xE0, 0x90, 0x90, 0x90, 0xE0, # D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, # E
    0xF0, 0x80, 0xF0, 0x80, 0x80  # F
].freeze

class OverflowError < StandardError

end

class Timer
  attr_reader :ticks
  def initialize
    @ticks = 0
  end

  def set(ticks)
    raise OverflowError if @ticks < 0
    @ticks = ticks
  end

  def count_down
    raise OverflowError if @ticks == 0
    @ticks-=1
  end

  def ticking?
    @ticks > 0
  end
end

class InputPort
  # @param [Registers] input_registers
  def initialize(input_registers:)
    @input_registers = input_registers
  end

  def update
    raise NotImplementedError
  end
end

class DefaultInputPort < InputPort
  # @param [InputRegisters] input_registers
  # @param [Window] window
  def initialize(input_registers:, window:)
    @window = window
    super(input_registers: input_registers)
  end

  def update
    keys = @window.keys_states
    keys.each_with_index { |state, key_index| @input_registers.update_register(key_index, state) }
  end
end


class Display
  def initialize
    @redraw = false
  end

  def schedule_redraw
    @redraw = true
  end

  def draw
    raise NotImplementedError
  end
end

class DefaultDisplay < Display
  # @param [Vram] vram
  # @param [Window] window
  def initialize(vram:, window:)
    @vram = vram
    @window = window
  end

  def draw
    return unless @redraw
    pixels = []
    @vram.height.times do |y|
      @vram.width.times do |x|
        pixels << [x, y] if @vram.read(address: (y*64) + x) != 0x0
      end
    end
    @redraw = false
    @window.pixels = pixels
  end
end

class DebuggerDisplay < Display
  # @param [Vram] vram
  def initialize(vram:)
    @vram = vram
  end

  def draw
    return unless @redraw
    system('clear')
    32.times do |y|
      64.times do |x|
        if @vram.read(address: (y*64) + x) == 0x0
          printf("0")
        else
          printf(" ")
        end
      end
      printf("\n")
    end
    printf("\n")
  end
end

class Memory
  def initialize(size_in_bytes:, item_size_in_bits:)
    @buffer = Array.new(size_in_bytes, 0x0)
    @item_size_in_bits = item_size_in_bits
  end

  def write(position, data)
    validate_position!(position)
    validate_data!(data)
    @buffer[position] = data
  end

  def read_all
    @buffer
  end

  def clear_all
    @buffer = Array.new(@buffer.size, 0x0)
  end

  # @param [Register] register
  # @param [Integer] address
  # @param [Integer] bytes_count
  def read(register: nil, address: nil, bytes_count: 1)
    start_memory_position = register.nil? ? address : register.read
    end_memory_position = start_memory_position + bytes_count - 1

    validate_position!(start_memory_position)
    validate_position!(end_memory_position)

    @buffer[(start_memory_position)..(end_memory_position)].inject(0x0000) {|acc, byte| (acc << @item_size_in_bits) | byte}
  end

  def to_s
    "#{@buffer}"
  end

  def validate_position!(position)
    raise OverflowError,
          "invalid position. value #{position} has to be between [0,#{@buffer.size-1}]" unless position >= 0 && position < @buffer.size
  end

  private :validate_position!

  def validate_data!(data)
    raise OverflowError, "invalid data #{data.to_s(16)}. It has to be less than #{@item_size_in_bits} bits" unless (data >> @item_size_in_bits) == 0
  end

  private :validate_data!
end

class Ram < Memory
  def initialize
    super(size_in_bytes: 4_096, item_size_in_bits: 8)
  end
end

class Vram < Memory
  attr_reader :width
  attr_reader :height
  # @param [Integer] width
  # @param [Integer] height
  def initialize(width:, height:)
    @width = width
    @height = height
    super(size_in_bytes: (width * height), item_size_in_bits: 1)
  end
end

class Stack
  def initialize(levels:, item_size_in_bits:)
    @addresses = []
    @levels = levels
    @item_size_in_bits = item_size_in_bits
  end

  def push(data)
    raise OverflowError if (data >> @item_size_in_bits) > 0 || @addresses.size >= @levels
    @addresses.push(data)
  end

  def pop
    raise OverflowError if @addresses.size == 0
    @addresses.pop
  end

  def to_s
    "STACK: #{@addresses}"
  end
end

class Register
  def initialize(size_in_bits:, initial_data: 0x0, name:)
    raise OverflowError if (initial_data >> size_in_bits) > 0
    @data = initial_data
    @size_in_bits = size_in_bits
    @name = name
  end

  def update(data)
    raise OverflowError, "error updating register #{@name} limited to #{@size_in_bits} bits with value #{data.to_s(2)}" if (data >> @size_in_bits) > 0
    @data = data
  end

  def read
    @data
  end

  def add(data)
    updated_data = @data + data
    update(updated_data)
  end

  def ==(data)
    if data.is_a?(Integer)
      return @data == data
    elsif data.is_a?(Register) && data.class == self.class
      return @data == data.read
    end
    raise NotImplementedError
  end

  def to_s
    "#{@name}: #{@data}"
  end
end

class Registers
    # @param [Integer] count
    # @param [Integer] register_size_in_bits
    # @param [String] name
    # @param [String] register_name_prefix
    def initialize(count:, register_size_in_bits:, name: "REGISTERS", register_name_prefix:)
    @registers = Array.new(count) { |index| Register.new(size_in_bits: register_size_in_bits, name: "#{register_name_prefix}#{index.to_s(16).upcase}") }
    @name = name
  end

  def read_register(register_index)
    raise OverflowError unless register_index >= 0 && register_index < @registers.size
    @registers[register_index]
  end

  def update_register(register_index, data)
    raise OverflowError unless register_index >= 0 && register_index < @registers.size
    @registers[register_index].update(data)
  end

  def to_s
    "#{@name}:\n#{@registers.map(&:to_s).join("\n")}"
  end
end

class ProgramCounter < Register
  def initialize
    super(size_in_bits: 16, initial_data: 0x200, name: "PC")
  end
end

class MemoryAddress < Register
  def initialize
    super(size_in_bits: 12, name: "I")
  end
end

class InstructionId
  attr_reader :opcode
  @@default_comparator = -> (opcode, other_opcode) { opcode == other_opcode }

  # @param [Integer] opcode
  # @param [Proc] comparator
  def initialize(opcode=nil, &comparator)
    @opcode = opcode
    @comparator = comparator
  end

  # @param [InstructionId] other
  def eql?(other)
    other.matches_opcode?(@opcode) || matches_opcode?(other.opcode)
  end

  # @param [Integer] opcode
  # @return [TrueClass|FalseClass]
  def matches_opcode?(opcode)
    return @comparator.call(opcode) unless @comparator.nil?
    @@default_comparator.call(@opcode, opcode)
  end

  def hash
    1.hash
  end
end

class Chip8
  # @param [Array[Instruction]] instructions
  # @param [Ram] ram
  # @param [ProgramCounter] pc
  # @param [Registers] registers
  # @param [MemoryAddress] ma
  # @param [Stack] stack
  # @param [Display] display
  # @param [Timer] delay_timer
  # @param [Timer] sound_timer
  # @param [InputPort] input_port
  # @param [Speaker] speaker
  def initialize(instructions:, ram:, pc:, registers:, ma:, stack:, display:, delay_timer:, sound_timer:, input_port:, speaker:)
    @instructions_map = instructions.map{ |instruction| [instruction.instruction_id, instruction] }.to_h
    @ram = ram
    @pc = pc
    @registers = registers
    @ma = ma
    @stack = stack
    @display = display
    @delay_timer = delay_timer
    @sound_timer = sound_timer
    @input_port = input_port
    @speaker = speaker
  end

  def boot
    steady_loop(fps: 120) do
      code = @ram.read(register: @pc, bytes_count: 2)
      # puts "OPCODE: #{code.to_s(16)}"
      instruction = @instructions_map[InstructionId.new(code)]
      if instruction.nil?
        puts "WARN: no instruction implemented for #{code.to_s(16)}"
        break
      else
        # puts instruction
        instruction.execute(code)
      end
      @display.draw

      @delay_timer.count_down if @delay_timer.ticking?

      if @sound_timer.ticking?
        @speaker.play
        @sound_timer.count_down
      else
        @speaker.stop
      end

      @input_port.update
      # puts @pc
      # puts @ma
      # puts @stack
      # puts @registers
    end
  end

  # @param [Integer] fps
  def steady_loop(fps:,&proc)
    frame_ms = 1.to_f / fps.to_f
    loop do
      start_time_in_seconds = Time.now.to_f
      proc.call
      end_time_in_seconds = Time.now.to_f
      delay_in_seconds = frame_ms - (end_time_in_seconds - start_time_in_seconds)
      sleep delay_in_seconds if delay_in_seconds > 0.0
    end
  rescue StandardError => e
    puts "Unexpected error: #{e.message}"
    puts e.backtrace
    raise e
  end

  private :steady_loop
end

class Instruction
  attr_reader :instruction_id
  # @param [InstructionId] instruction_id
  def initialize(instruction_id:)
    @instruction_id = instruction_id
  end

  # @param [Integer] opcode
  def execute(opcode)
    raise NotImplementedError
  end

  def skip_opcode?(opcode)
    !@instruction_id.matches_opcode?(opcode)
  end

  def to_s
    "INSTRUCTION: #{self.class.name}"
  end
end

class ClearDisplay < Instruction
  # @param [Display] display
  # @param [Vram] vram
  # @param [ProgramCounter] pc
  def initialize(display:, vram:, pc:)
    @display = display
    @vram = vram
    @pc = pc
    super(instruction_id: InstructionId.new(0x00E0))
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    @vram.clear_all
    @pc.add(2)
    @display.schedule_redraw
  end
end

class ReturnFromSubroutine < Instruction
  # @param [Stack] stack
  # @param [ProgramCounter] pc
  def initialize(stack:, pc:)
    @stack = stack
    @pc = pc
    super(instruction_id: InstructionId.new(0x00EE))
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    @pc.update(@stack.pop)
    @pc.add(2)
  end
end

class Jump < Instruction
  # @param [ProgramCounter] pc
  def initialize(pc:)
    @pc = pc
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF000 == 0x1000 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    @pc.update(opcode & 0x0FFF)
  end
end

class Call < Instruction
  # @param [ProgramCounter] pc
  # @param [Stack] stack
  def initialize(pc:, stack:)
    @pc = pc
    @stack = stack
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF000 == 0x2000 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    @stack.push(@pc.read)
    @pc.update(opcode & 0x0FFF)
  end
end

class SkipRegisterEqualsValue < Instruction
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  def initialize(registers:, pc:)
    @registers = registers
    @pc = pc
    # 3xkk => Vx == kk
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF000 == 0x3000 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    register_index = (opcode & 0x0F00) >> 8
    if @registers.read_register(register_index) == opcode & 0x00FF
      @pc.add(4)
    else
      @pc.add(2)
    end
  end
end

class SkipRegisterNotEqualsValue < Instruction
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  def initialize(registers:, pc:)
    @registers = registers
    @pc = pc
    # 4xkk => Vx != kk
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF000 == 0x4000 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    register_index = (opcode & 0x0F00) >> 8
    if @registers.read_register(register_index) != opcode & 0x00FF
      @pc.add(4)
    else
      @pc.add(2)
    end
  end
end

class SkipRegisterEqualsRegister < Instruction
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  def initialize(registers:, pc:)
    @registers = registers
    @pc = pc
    # 5xy0 => Vx == kk
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF000 == 0x5000 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    first_register_index = (opcode & 0x0F00) >> 8
    second_register_index = (opcode & 0x00F0) >> 4
    if @registers.read_register(first_register_index) == @registers.read_register(second_register_index)
      @pc.add(4)
    else
      @pc.add(2)
    end
  end
end

class UpdateRegister < Instruction
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  def initialize(registers:, pc:)
    @registers = registers
    @pc = pc
    # 6xkk => Vx <= kk
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF000 == 0x6000 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    register_index = (opcode & 0x0F00) >> 8
    value = opcode & 0x00FF
    @registers.update_register(register_index, value)
    @pc.add(2)
  end
end

class AddToRegister < Instruction
  # @param [Registers] registers
  # # @param [ProgramCounter] pc
  def initialize(registers:, pc:)
    @registers = registers
    @pc = pc
    # 7xkk => Vx = Vx + kk
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF000 == 0x7000 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    register_index = (opcode & 0x0F00) >> 8
    value = opcode & 0x00FF
    current_value = @registers.read_register(register_index).read
    sum = value + current_value
    @registers.update_register(register_index, sum & 0xFF)
    @pc.add(2)
  end
end

class Copy < Instruction
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  def initialize(registers:, pc:)
    @registers = registers
    @pc = pc
    # 8xy0 => Vx = Vy
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF00F == 0x8000 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    first_register_index = (opcode & 0x0F00) >> 8
    second_register_index = (opcode & 0x00F0) >> 4

    second_register_value = @registers.read_register(second_register_index).read
    @registers.update_register(first_register_index, second_register_value)
    @pc.add(2)
  end
end

class Or < Instruction
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  def initialize(registers:, pc:)
    @registers = registers
    @pc = pc
    # 8xy1 => Vx = Vx | Vy
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF00F == 0x8001 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    first_register_index = (opcode & 0x0F00) >> 8
    second_register_index = (opcode & 0x00F0) >> 4

    first_register_value = @registers.read_register(first_register_index).read
    second_register_value = @registers.read_register(second_register_index).read
    @registers.update_register(first_register_index, first_register_value | second_register_value)
    @pc.add(2)
  end
end

class And < Instruction
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  def initialize(registers:, pc:)
    @registers = registers
    @pc = pc
    # 8xy2 => Vx = Vx & Vy
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF00F == 0x8002 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    first_register_index = (opcode & 0x0F00) >> 8
    second_register_index = (opcode & 0x00F0) >> 4

    first_register_value = @registers.read_register(first_register_index).read
    second_register_value = @registers.read_register(second_register_index).read
    @registers.update_register(first_register_index, first_register_value & second_register_value)
    @pc.add(2)
  end
end

class Xor < Instruction
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  def initialize(registers:, pc:)
    @registers = registers
    @pc = pc
    # 8xy3 => Vx = Vx ^ Vy
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF00F == 0x8003 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    first_register_index = (opcode & 0x0F00) >> 8
    second_register_index = (opcode & 0x00F0) >> 4

    first_register_value = @registers.read_register(first_register_index).read
    second_register_value = @registers.read_register(second_register_index).read
    @registers.update_register(first_register_index, first_register_value ^ second_register_value)
    @pc.add(2)
  end
end

class SumRegisters < Instruction
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  def initialize(registers:, pc:)
    @registers = registers
    @pc = pc
    # 8xy4 => Vx = Vx + Vy, VF = carry
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF00F == 0x8004 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    first_register_index = (opcode & 0x0F00) >> 8
    second_register_index = (opcode & 0x00F0) >> 4

    first_register_value = @registers.read_register(first_register_index).read
    second_register_value = @registers.read_register(second_register_index).read
    sum = first_register_value + second_register_value

    @registers.update_register(0x0F, 0x01) if sum > 0xFF
    @registers.update_register(first_register_index, sum & 0xFF)
    @pc.add(2)
  end
end

class SubRegisters < Instruction
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  def initialize(registers:, pc:)
    @registers = registers
    @pc = pc
    # 8xy5 => Vx = Vx - Vy, VF = NOT borrow
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF00F == 0x8005 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    first_register_index = (opcode & 0x0F00) >> 8
    second_register_index = (opcode & 0x00F0) >> 4

    first_register_value = @registers.read_register(first_register_index).read
    second_register_value = @registers.read_register(second_register_index).read

    sub = first_register_value - second_register_value

    if sub < 0x00
      sub += 256
      @registers.update_register(0x0F, 0x00)
    else
      @registers.update_register(0x0F, 0x01)
    end

    @registers.update_register(first_register_index, sub)
    @pc.add(2)
  end
end

class ShiftRightRegisters < Instruction
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  def initialize(registers:, pc:)
    @registers = registers
    @pc = pc
    # 8xy6 => Vx=Vy>>1,  VF = Vy & 0x01
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF00F == 0x8006 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    first_register_index = (opcode & 0x0F00) >> 8
    second_register_index = (opcode & 0x00F0) >> 4

    second_register_value = @registers.read_register(second_register_index).read
    @registers.update_register(0x0F, second_register_value & 0x01)
    @registers.update_register(first_register_index, second_register_value >> 0x01)
    @pc.add(2)
  end
end

class SubbRegisters < Instruction
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  def initialize(registers:, pc:)
    @registers = registers
    @pc = pc
    # 8xy5 => Vx = Vy - Vx, VF = NOT borrow
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF00F == 0x8007 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    first_register_index = (opcode & 0x0F00) >> 8
    second_register_index = (opcode & 0x00F0) >> 4

    first_register_value = @registers.read_register(first_register_index).read
    second_register_value = @registers.read_register(second_register_index).read
    sub = second_register_value - first_register_value

    if sub < 0x00
      sub += 256
      @registers.update_register(0x0F, 0x00)
    else
      @registers.update_register(0x0F, 0x01)
    end

    @registers.update_register(first_register_index, sub)
    @pc.add(2)
  end
end

class ShiftLeftRegisters < Instruction
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  def initialize(registers:, pc:)
    @registers = registers
    @pc = pc
    # 8xyE => Vx=Vy<<1,  VF = Vy & 0x01
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF00F == 0x800E })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    first_register_index = (opcode & 0x0F00) >> 8
    second_register_index = (opcode & 0x00F0) >> 4

    second_register_value = @registers.read_register(second_register_index).read
    @registers.update_register(0x0F, second_register_value & 0x80 != 0 ? 0x01 : 0x00)
    @registers.update_register(first_register_index, second_register_value << 0x01)
    @pc.add(2)
  end
end

class SkipRegisterNotEqualsRegister < Instruction
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  def initialize(registers:, pc:)
    @registers = registers
    @pc = pc
    # 9xy0 => Vx != Vy
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF00F == 0x9000 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    first_register_index = (opcode & 0x0F00) >> 8
    second_register_index = (opcode & 0x00F0) >> 4
    if @registers.read_register(first_register_index) != @registers.read_register(second_register_index)
      @pc.add(4)
    else
      @pc.add(2)
    end
  end
end

class SetMemoryAddressRegisterToValue < Instruction
  # @param [MemoryAddress] ma
  # @param [ProgramCounter] pc
  def initialize(ma:, pc:)
    @ma = ma
    @pc = pc
    # Annn
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF000 == 0xA000 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    address = opcode & 0x0FFF
    @ma.update(address)
    @pc.add(2)
  end
end

class JumpToV0 < Instruction
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  def initialize(registers:, pc:)
    @registers = registers
    @pc = pc
    # Bnnn
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF000 == 0xB000 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    @pc.add((opcode & 0x0FFF) + @registers.read_register(0x0).read)
  end
end

class RandToRegister < Instruction
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  def initialize(registers:, pc:)
    @registers = registers
    @pc = pc
    # Cxkk
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF000 == 0xC000 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    register_index = (opcode & 0x0F00) >> 8
    value = (opcode & 0x00FF) & rand(0xFF)
    @registers.update_register(register_index, value)
    @pc.add(2)
  end
end

class Draw < Instruction
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  # @param [MemoryAddress] ma
  # @param [Vram] vram
  # @param [Display] display
  # @param [Ram] ram
  def initialize(registers:, pc:, ma:, vram:, display:, ram:)
    @registers = registers
    @pc = pc
    @ma = ma
    @vram = vram
    @display = display
    @ram = ram
    # Dxyn
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF000 == 0xD000 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    first_register_index = (opcode & 0x0F00) >> 8
    second_register_index = (opcode & 0x00F0) >> 4
    height = opcode & 0x000F
    x = @registers.read_register(first_register_index).read
    y = @registers.read_register(second_register_index).read
    @registers.update_register(0x0F, 0x00)

    height.times do |dy|
      pixels = @ram.read(address: (@ma.read + dy))
      8.times.each do |dx|
        next if pixels & ((0b10000000 >> dx)) == 0
        x_coordinate = (x + dx) % @vram.width
        y_coordinate = (y + dy) % @vram.height
        pixel_index = (x_coordinate + (y_coordinate * 64))
        pixel = @vram.read(address: pixel_index)
        @registers.update_register(0x0F, 0x01) if pixel == 1

        @vram.write(pixel_index, pixel ^ 1)
      end
    end
    @display.schedule_redraw
    @pc.add(2)
  end
end

class SkipIfKeyPressed < Instruction
  # @param [Registers] input_registers
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  def initialize(input_registers:, registers:, pc:)
    @input_registers = input_registers
    @registers = registers
    @pc = pc
    # Ex9E
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF0FF == 0xE09E })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    register_index = (opcode & 0x0F00) >> 8
    key_id = @registers.read_register(register_index).read
    key_pressed = @input_registers.read_register(key_id).read == 0x1
    if key_pressed
      @pc.add(4)
    else
      @pc.add(2)
    end
  end
end

class SkipIfKeyNotPressed < Instruction
  # @param [Registers] input_registers
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  def initialize(input_registers:, registers:, pc:)
    @input_registers = input_registers
    @registers = registers
    @pc = pc
    # ExA1
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF0FF == 0xE0A1 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    register_index = (opcode & 0x0F00) >> 8
    key_id = @registers.read_register(register_index).read
    key_not_pressed = @input_registers.read_register(key_id).read == 0x0
    if key_not_pressed
      @pc.add(4)
    else
      @pc.add(2)
    end
  end
end

class SetRegisterToDelayTimer < Instruction
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  # @param [Timer] delay_timer
  def initialize(registers:, pc:, delay_timer:)
    @registers = registers
    @pc = pc
    @delay_timer = delay_timer
    # Fx07
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF0FF == 0xF007 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    register_index = (opcode & 0x0F00) >> 8
    @registers.update_register(register_index, @delay_timer.ticks)
    @pc.add(2)
  end
end

class WaitKeyPressed < Instruction
  # @param [Registers] input_registers
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  def initialize(input_registers:, registers:, pc:)
    @input_registers = input_registers
    @registers = registers
    @pc = pc
    # Fx0A
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF0FF == 0xF00A })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    register_index = (opcode & 0x0F00) >> 8
    register_index = @registers.read_register(register_index).read

    0x00.upto(0xF).each do |key_id|
      key_pressed = @input_registers.read_register(key_id).read == 0x1
      if key_pressed
        @pc.add(2)
        @registers.update_register(register_index, key_id) if key_pressed
        break
      end
    end
  end
end


class SetDelayTimer < Instruction
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  # @param [Timer] delay_timer
  def initialize(registers:, pc:, delay_timer:)
    @registers = registers
    @pc = pc
    @delay_timer = delay_timer
    # Fx15
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF0FF == 0xF015 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    register_index = (opcode & 0x0F00) >> 8
    register_value = @registers.read_register(register_index).read
    @delay_timer.set(register_value)
    @pc.add(2)
  end
end

class SetSoundTimer < Instruction
  # @param [Registers] registers
  # @param [ProgramCounter] pc
  # @param [Timer] sound_timer
  def initialize(registers:, pc:, sound_timer:)
    @registers = registers
    @pc = pc
    @sound_timer = sound_timer
    # Fx18
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF0FF == 0xF018 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    register_index = (opcode & 0x0F00) >> 8
    register_value = @registers.read_register(register_index).read
    @sound_timer.set(register_value)
    @pc.add(2)
  end
end

class IncrementMemoryAddressRegisterWithRegisterValue < Instruction
  # @param [Registers] registers
  # @param [MemoryAddress] ma
  # @param [ProgramCounter] pc
  def initialize(registers:, ma:, pc:)
    @ma = ma
    @pc = pc
    @registers = registers
    # Fx1E
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF0FF == 0xF01E })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    register_index = (opcode & 0x0F00) >> 8
    register_value = @registers.read_register(register_index).read
    @ma.add(register_value)
    @pc.add(2)
  end
end

class SetMemoryAddressRegisterToCharacter < Instruction
  # @param [Registers] registers
  # @param [MemoryAddress] ma
  # @param [ProgramCounter] pc
  def initialize(registers:, ma:, pc:)
    @ma = ma
    @pc = pc
    @registers = registers
    # Fx29
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF0FF == 0xF029 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    register_index = (opcode & 0x0F00) >> 8
    register_value = @registers.read_register(register_index).read
    @ma.update(register_value*0x05)
    @pc.add(2)
  end
end

class UpdateRamWithRegisterAsBCDRepresentation < Instruction
  # @param [Registers] registers
  # @param [MemoryAddress] ma
  # @param [ProgramCounter] pc
  # @param [Ram] ram
  def initialize(registers:, ma:, pc:, ram:)
    @registers = registers
    @ma = ma
    @pc = pc
    @ram = ram
    # Fx33
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF0FF == 0xF033 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    register_index = (opcode & 0x0F00) >> 8
    register_value = @registers.read_register(register_index).read
    memory_address = @ma.read

    @ram.write(memory_address, register_value / 100)
    @ram.write(memory_address + 1, (register_value / 10) % 10)
    @ram.write(memory_address + 2, (register_value % 100) % 10)
    @pc.add(2)
  end
end

class BatchLoadRegisterWithRamValues < Instruction
  # @param [Registers] registers
  # @param [MemoryAddress] ma
  # @param [ProgramCounter] pc
  # @param [Ram] ram
  def initialize(registers:, ma:, pc:, ram:)
    @registers = registers
    @ma = ma
    @pc = pc
    @ram = ram
    # Fx33
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF0FF == 0xF065 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    last_register_index = (opcode & 0x0F00) >> 8

    0.upto(last_register_index).each do |register_index|
      memory_address = @ma.read
      @registers.update_register(register_index, @ram.read(register: @ma))
      @ma.update(memory_address+1)
    end
    @pc.add(2)
  end
end


window = Window.new(scale: 10)

pc = ProgramCounter.new
ma = MemoryAddress.new
stack = Stack.new(levels: 16, item_size_in_bits: 16)
registers = Registers.new(count: 16, register_size_in_bits: 8, name: "DATA", register_name_prefix: "V")
input_registers = Registers.new(count: 16, register_size_in_bits: 1, name: "INPUT", register_name_prefix: "I")
ram = Ram.new
vram = Vram.new(width: 64, height: 32)
delay_timer = Timer.new
sound_timer = Timer.new

display = DefaultDisplay.new(vram: vram, window: window)
  # display = DebuggerDisplay.new(vram: vram)

input_port = DefaultInputPort.new(input_registers: input_registers, window: window)

# @param [Ram] ram
def load_fonts(ram:)
  CHARS_MAP.each_with_index {|byte, position| ram.write(position, byte) }
end

# @param [Ram] ram
# @param [ProgramCounter] pc
def load_rom(ram:, pc:)
  contents = IO.binread(File.join(__dir__, '../roms/pong2.c8'))

  write_position = pc.read
  contents.each_byte do |b|
    ram.write(write_position, b)
    write_position+=1
  end
end

instructions = [
    ClearDisplay.new(display: display, vram: vram, pc: pc),
    ReturnFromSubroutine.new(stack: stack, pc: pc),
    Jump.new(pc: pc),
    Call.new(stack: stack, pc: pc),
    SkipRegisterEqualsValue.new(registers: registers, pc: pc),
    SkipRegisterNotEqualsValue.new(registers: registers, pc: pc),
    SkipRegisterEqualsRegister.new(registers: registers, pc: pc),
    UpdateRegister.new(registers: registers, pc: pc),
    AddToRegister.new(registers: registers, pc: pc),
    Copy.new(registers: registers, pc: pc),
    Or.new(registers: registers, pc: pc),
    And.new(registers: registers, pc: pc),
    Xor.new(registers: registers, pc: pc),
    SumRegisters.new(registers: registers, pc: pc),
    SubRegisters.new(registers: registers, pc: pc),
    ShiftRightRegisters.new(registers: registers, pc: pc),
    SubbRegisters.new(registers: registers, pc: pc),
    ShiftLeftRegisters.new(registers: registers, pc: pc),
    SkipRegisterNotEqualsRegister.new(registers: registers, pc: pc),
    SetMemoryAddressRegisterToValue.new(ma: ma, pc: pc),
    JumpToV0.new(registers: registers, pc: pc),
    RandToRegister.new(registers: registers, pc: pc),
    Draw.new(registers: registers, pc: pc, ma: ma, vram: vram, display: display, ram: ram),
    SkipIfKeyNotPressed.new(registers: registers, input_registers: input_registers, pc: pc),
    SkipIfKeyPressed.new(registers: registers, input_registers: input_registers, pc: pc),
    SetRegisterToDelayTimer.new(registers: registers, delay_timer: delay_timer, pc: pc),
    WaitKeyPressed.new(input_registers: input_registers, registers: registers, pc: pc),
    SetDelayTimer.new(registers: registers, delay_timer: delay_timer, pc: pc),
    SetSoundTimer.new(registers: registers, sound_timer: sound_timer, pc: pc),
    IncrementMemoryAddressRegisterWithRegisterValue.new(registers: registers, ma: ma, pc: pc),
    SetMemoryAddressRegisterToCharacter.new(registers: registers, ma: ma, pc: pc),
    UpdateRamWithRegisterAsBCDRepresentation.new(registers: registers, pc: pc, ram: ram, ma: ma),
    BatchLoadRegisterWithRamValues.new(registers: registers, pc: pc, ram: ram, ma: ma)
]

load_fonts(ram: ram)
load_rom(ram: ram, pc: pc)

chip8 = Chip8.new(instructions: instructions,
                  ram: ram,
                  pc: pc,
                  registers: registers,
                  ma: ma,
                  stack: stack,
                  display: display,
                  delay_timer: delay_timer,
                  sound_timer: sound_timer,
                  input_port: input_port,
                  speaker: Speaker.new)

pool = Concurrent::FixedThreadPool.new(1)
pool.post do
  chip8.boot
end
window.show

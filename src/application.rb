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

class Display
  def clear

  end
end

class DumbDisplay < Display
  def initialize
    @pixels = Array.new(2048, 0x0)
  end

  def clear
    @pixels = Array.new(2048, 0x0)
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

  # @param [Register] register
  # @param [Integer] length
  def read(register:, length: 1)
    validate_position!(register.read)
    validate_position!(register.read + length)
    @buffer[(register.read)..(register.read+length)].inject(0x0000) {|acc, byte| (acc << 8) | byte} >> 8
  end

  def to_s
    "#{@buffer}"
  end

  def validate_position!(position)
    raise OverflowError unless position >= 0 && position < @buffer.size
  end

  private :validate_position!

  def validate_data!(data)
    raise OverflowError unless (data >> @item_size_in_bits) == 0
  end

  private :validate_data!
end

class Ram < Memory
  def initialize
    super(size_in_bytes: 4_096, item_size_in_bits: 8)
  end
end

class Vram < Memory
  def initialize
    super(size_in_bytes: 2_048, item_size_in_bits: 1)
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
    raise OverflowError if (data >> @size_in_bits) > 0
    @data = data
  end

  def read
    @data
  end

  def add(data)
    @data += data
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
  def initialize(count:, register_size_in_bits:, name: "REGISTERS")
    @registers = Array.new(count) { |index| Register.new(size_in_bits: register_size_in_bits, name: "V#{index}") }
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

class ProgramRunner
  # @param [Array[Instruction]] instructions
  # @param [Ram] ram
  # @param [ProgramCounter] pc
  # @param [Registers] registers
  # @param [MemoryAddress] ma
  # @param [Stack] stack
  def initialize(instructions:, ram:, pc:, registers:, ma:, stack:)
    @instructions_map = instructions.map{ |instruction| [instruction.instruction_id, instruction] }.to_h
    @ram = ram
    @pc = pc
    @registers = registers
    @ma = ma
    @stack = stack
  end

  def start
    while true
      code = @ram.read(register: @pc, length: 2)
      puts "OPCODE: #{code.to_s(16)}"
      instruction = @instructions_map[InstructionId.new(code)]
      if instruction.nil?
        puts "WARN: no instruction implemented for #{code.to_s(16)}"
      else
        puts instruction
        instruction.execute(code)
      end

      puts @pc
      puts @ma
      puts @stack
      puts @registers
      puts "waiting for input"
      next gets == "n"
      break if gets == "q"
    end
  end
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
  def initialize(display:)
    @display = display
    super(instruction_id: InstructionId.new(0x00E0))
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    @display.clear
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
    puts "TODO: implement me"
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
    @pc.add(2) if @registers.read_register(register_index) == opcode & 0x00FF
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
    @pc.add(2) if @registers.read_register(register_index) != opcode & 0x00FF
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
    @pc.add(2) if @registers.read_register(first_register_index) == @registers.read_register(second_register_index)
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
    @registers.update_register(register_index, value + current_value)
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
    @registers.update_register(first_register_index, sum & 0xFF)
    @registers.update_register(0x0F, 0x01) if sum >> 8 > 0
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
    @registers.update_register(0x0F, 0x01) if first_register_value > second_register_value
    @registers.update_register(first_register_index, first_register_value - second_register_value)
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
    @registers.update_register(0x0F, 0x01) if second_register_value > first_register_value
    @registers.update_register(first_register_index, second_register_value - first_register_value)
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
    @pc.add(2) if @registers.read_register(first_register_index) != @registers.read_register(second_register_index)
  end
end

class SetMemoryAddressRegister < Instruction
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
  # @param [Vram] vram
  def initialize(registers:, pc:, vram:)
    @registers = registers
    @pc = pc
    @vram = vram
    # Dxyn
    super(instruction_id: InstructionId.new {|opcode| opcode & 0xF000 == 0xD000 })
  end

  def execute(opcode)
    return if skip_opcode?(opcode)
    # register_index = (opcode & 0x0F00) >> 8
    # value = (opcode & 0x00FF) & rand(0xFF)
    # @registers.update_register(register_index, value)
    # TODO: implement me
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
    @ma.update(register_value*5)
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


display = DumbDisplay.new
pc = ProgramCounter.new

ma = MemoryAddress.new
stack = Stack.new(levels: 16, item_size_in_bits: 16)
registers = Registers.new(count: 16, register_size_in_bits: 8)
ram = Ram.new
vram = Vram.new

debug = false
if debug
  ClearDisplay.new(display: display).execute(0x0)
  ReturnFromSubroutine.new(stack: stack, pc: pc).execute(0x0)
  Jump.new(pc: pc).execute(0xFFFF)
  Call.new(stack: stack, pc: pc).execute(0xFFFF)
  SkipRegisterEqualsValue.new(registers: registers, pc: pc).execute(0xFFFF)
  SkipRegisterNotEqualsValue.new(registers: registers, pc: pc).execute(0xFFFF)
  SkipRegisterEqualsRegister.new(registers: registers, pc: pc).execute(0xFFFF)
  UpdateRegister.new(registers: registers, pc: pc).execute(0xFFFF)
  AddToRegister.new(registers: registers, pc: pc).execute(0xF104)
  Copy.new(registers: registers, pc: pc).execute(0xF210)
  Or.new(registers: registers, pc: pc).execute(0x8411)
  And.new(registers: registers, pc: pc).execute(0x8512)
  Xor.new(registers: registers, pc: pc).execute(0x8213)
  SumRegisters.new(registers: registers, pc: pc).execute(0x8144)
  SubRegisters.new(registers: registers, pc: pc).execute(0x8145)
  ShiftRightRegisters.new(registers: registers, pc: pc).execute(0x8246)
  SubbRegisters.new(registers: registers, pc: pc).execute(0x8246)
  ShiftLeftRegisters.new(registers: registers, pc: pc).execute(0x8426)
  SkipRegisterNotEqualsRegister.new(registers: registers, pc: pc).execute(0xFFFF)
  SetMemoryAddressRegister.new(ma: ma, pc: pc).execute(0xA333)
  JumpToV0.new(registers: registers, pc: pc).execute(0xB222)
  RandToRegister.new(registers: registers, pc: pc).execute(0xC7FF)
  Draw.new(registers: registers, pc: pc, vram: vram).execute(0xD003)

  puts pc
  puts ma
  puts stack
  puts registers
  exit 0
end

# @param [Ram] ram
def load_fonts(ram:)
  CHARS_MAP.each_with_index {|byte, position| ram.write(position, byte) }
end

# @param [Ram] ram
# @param [ProgramCounter] pc
def load_rom(ram:, pc:)
  contents = IO.binread(File.join(__dir__, '../roms/pong.rom'))

  write_position = pc.read
  contents.each_byte do |b|
    ram.write(write_position, b)
    write_position+=1
  end
end


instructions = [
    ClearDisplay.new(display: display),
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
    SetMemoryAddressRegister.new(ma: ma, pc: pc),
    JumpToV0.new(registers: registers, pc: pc),
    RandToRegister.new(registers: registers, pc: pc),
    Draw.new(registers: registers, pc: pc, vram: vram),
    UpdateRamWithRegisterAsBCDRepresentation.new(registers: registers, pc: pc, ram: ram, ma: ma),
    BatchLoadRegisterWithRamValues.new(registers: registers, pc: pc, ram: ram, ma: ma),
    SetMemoryAddressRegisterToCharacter.new(registers: registers, ma: ma, pc: pc)
]

load_fonts(ram: ram)
load_rom(ram: ram, pc: pc)

runner = ProgramRunner.new(instructions: instructions,
                           ram: ram,
                           pc: pc,
                           registers: registers,
                           ma: ma,
                           stack: stack)
runner.start


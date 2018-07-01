class Window < Gosu::Window
  attr_writer :pixels

  INPUT_KEYS = {
      Gosu::Kb1 => 0x1,
      Gosu::Kb2 => 0x2,
      Gosu::Kb3 => 0x3,
      Gosu::Kb4 => 0xC,
      Gosu::KbQ => 0x4,
      Gosu::KbW => 0x5,
      Gosu::KbE => 0x6,
      Gosu::KbR => 0xD,
      Gosu::KbA => 0x7,
      Gosu::KbS => 0x8,
      Gosu::KbD => 0x9,
      Gosu::KbF => 0xE,
      Gosu::KbZ => 0xA,
      Gosu::KbX => 0x0,
      Gosu::KbC => 0xB,
      Gosu::KbV => 0xF,
  }

  WIDTH = 64
  HEIGHT = 32
  def initialize(scale: 1)
    @scale = scale
    super WIDTH * scale, HEIGHT * scale
    self.caption = "Window"
    @pixels = []
    @keys = Array.new(INPUT_KEYS.size, 0x0)
  end

  def keys_states
    @keys.dup
  end

  def button_down(key_id)
    mapped_key = INPUT_KEYS[key_id]
    @keys[mapped_key] = 0x1 unless mapped_key.nil?
  end

  def button_up(key_id)
    mapped_key = INPUT_KEYS[key_id]
    @keys[mapped_key] = 0x0 unless mapped_key.nil?
  end

  def update
  end

  def draw
    @pixels.each { |x, y| Gosu.draw_rect(x * @scale, y * @scale, @scale, @scale, Gosu::Color::WHITE)}
  end
end
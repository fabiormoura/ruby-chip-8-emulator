class Window < Gosu::Window
  attr_writer :pixels
  WIDTH = 64
  HEIGHT = 32
  def initialize(scale: 1)
    @scale = scale
    super WIDTH * scale, HEIGHT * scale
    self.caption = "Window"
    @pixels = []
  end

  def update
  end

  def draw
    @pixels.each { |x, y| Gosu.draw_rect(x * @scale, y * @scale, @scale, @scale, Gosu::Color::WHITE)}
  end
end
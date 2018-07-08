class Speaker
  def initialize
    @sample = Gosu::Sample.new(File.join(__dir__, '../data/beep.mp3'))
  end

  def play
    return if @channel&.playing?
    @channel = @sample.play(1,1,true)
  end

  def stop
    @channel.stop if @channel
  end
end
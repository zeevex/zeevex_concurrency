module ZeevexConcurrency::Delayed::ForEach
  #
  # As with lists, foreach executes the block once for each value present.
  # In the world of Delayeds, that means the block is called upon the
  # result value of the block *if* the Delayed is successful. If it failed,
  # the block is not called.
  #
  # @note This is a bit of weirdness taken from Scala.
  #
  # @yield [value] the value of the Future, unless failed.
  # @return the result of the block *if* it is called; though this method is primarily
  #    intended to be called to produce side effects.
  #
  def foreach
    wait
    yield value unless exception?
  end
end

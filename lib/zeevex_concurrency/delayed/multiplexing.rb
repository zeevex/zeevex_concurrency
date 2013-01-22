module ZeevexConcurrency::Delayed::Multiplexing
  #
  # Returns the first Delayed (Future, Promise, etc.) to complete, whether
  # with success or failure.
  #
  # Requires that the Delayed object implement the #onComplete method.
  #
  # @param [Delayed, #onComplete] other another Future/Promise/etc.
  # @return [Delayed] the first Delayed object to complete
  #
  def either(other)
    ZeevexConcurrency::Multiplex.either(self, other)
  end
end

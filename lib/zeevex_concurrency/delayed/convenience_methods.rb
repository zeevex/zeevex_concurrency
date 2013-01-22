module ZeevexConcurrency::Delayed::ConvenienceMethods
  # @see ZeevexConcurrency::Future.create
  def future(*args, &block)
    ZeevexConcurrency::Future.__send__(:create, *args, &block)
  end

  # @see ZeevexConcurrency::Promise.create
  def promise(*args, &block)
    ZeevexConcurrency::Promise.__send__(:create, *args, &block)
  end

  # @see ZeevexConcurrency::Delay.create
  def delay(*args, &block)
    ZeevexConcurrency::Delay.__send__(:create, *args, &block)
  end

  #
  # Check to see whether an object is a Delayed/Deferred wrapper.
  # Returns true for Futures, Promises, and Delays.
  #
  # @param [Object] obj the object to be checked
  # @return [Boolean] true if it's a Delayed
  #
  def delayed?(obj)
    obj.is_a?(ZeevexConcurrency::Delayed)
  end

  #
  # Check to see whether an object is a Delayed/Deferred wrapper.
  # Returns true for Delays.
  #
  # @param [Object] obj the object to be checked
  # @return [Boolean] true if it's a Delay
  #
  def delay?(obj)
    obj.is_a?(ZeevexConcurrency::Delay)
  end

  #
  # Check to see whether an object is a Delayed/Deferred wrapper.
  # Returns true for Promises.
  #
  # @param [Object] obj the object to be checked
  # @return [Boolean] true if it's a Promise
  #
  def promise?(obj)
    obj.is_a?(ZeevexConcurrency::Promise)
  end

  #
  # Check to see whether an object is a Delayed/Deferred wrapper.
  # Returns true for Futures.
  #
  # @param [Object] obj the object to be checked
  # @return [Boolean] true if it's a Future
  #
  def future?(obj)
    obj.is_a?(ZeevexConcurrency::Future)
  end
end

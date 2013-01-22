module ZeevexConcurrency::Delayed::LatchBased
  #
  # Waits until the Delayed completed. If the Delayed has not completed yet,
  # will block until it does. If it has completed, returns immediately.
  #
  # If a timeout is supplied, will wait no longer tham `timeout` seconds.
  #
  # @param [Integer, nil] timeout if supplied and non-nil, the max seconds to wait
  # @return [Object] true on success, false on timeout
  #
  def wait(timeout = nil)
    @_latch.wait(timeout)
  end

  def ready?
    @_latch.count == 0
  end

  protected

  def _initialize_latch
    @_latch = CountDownLatch.new(1)
  end

  def _fulfill(value, success = true)
    @result = value
    @ready  = true
    @_latch.countdown!
  end

  def _wait_for_value
    @_latch.wait
    @result
  end
end

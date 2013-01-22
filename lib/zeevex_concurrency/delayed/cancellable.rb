module ZeevexConcurrency::Delayed::Cancellable
  #
  # Determine whether a Future has been cancelled
  #
  # @return [Boolean] whether this Future has been cancelled
  #
  def cancelled?
    @cancelled
  end

  #
  # Prevents a Future from executing if it has not already completed. In
  # effect, this removes an incomplete Future from its worker queue. It
  # also marks the Future as failed with a CancelledException.
  #
  # @return [Boolean] true if the Future has been cancelled, false
  #    if it already completed and thus cannot be cancelled.
  #
  def cancel
    @exec_mutex.synchronize do
      return false if executed?
      return true  if cancelled?
      @cancelled = true
      smash CancelledException.new
      true
    end
  end

  #
  # Determine whether the Future is complete.
  #
  # @return [Boolean] true if the Future has completed or been cancelled
  #
  def ready?
    cancelled? || super
  end
end

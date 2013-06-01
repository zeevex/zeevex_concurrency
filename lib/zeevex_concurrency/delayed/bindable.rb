module ZeevexConcurrency::Delayed::Bindable
  # @private
  def bound?
    !! @binding
  end

  # @private
  def binding
    @binding
  end

  # @private
  def bind(proccy = nil, &block)
    raise "Already bound" if bound?
    if proccy && block
      raise ArgumentError, "must supply a callable OR a block or neither, but not both"
    end
    raise ArgumentError, "Must provide computation as proc or block" unless (proccy || block)
    @binding = proccy || block
  end

  #
  # Evaluate the block attached to this Delayed.
  #
  # @api private
  def execute
    @exec_mutex.synchronize do
      return if executed?
      return if respond_to?(:cancelled?) && cancelled?
      _execute(binding)
    end
  end

  # @api private
  alias_method :call, :execute
end

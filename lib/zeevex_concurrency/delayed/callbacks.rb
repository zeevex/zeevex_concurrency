module ZeevexConcurrency::Delayed::Callbacks
  def self.included(base)
    base.class_eval do
      alias_method :fulfill_without_callbacks, :fulfill
      alias_method :fulfill, :fulfill_with_callbacks
    end
  end

  #
  # Add a callback on a Future to receive value on success.
  #
  # This ensures that an observer receives a value even after the value has
  # become available. If the Future has already completed, the callback will
  # be called on the thread calling `onSuccess`, otherwise it will be called
  # from the thread on which the future has completed.
  #
  # @param [Block] observer the callback proc
  # @yieldparam [Object] value the result of the Future's evaluation
  #
  def onSuccess(&observer)
    @mutex.synchronize do
      if ready? && @success
        observer.call(value(false)) rescue nil
      else
        add_callback(:success, observer)
      end
    end
    self
  end

  #
  # Add a callback on a Future to receive value on failure.
  #
  # This ensures that an observer receives the callback even after the value has
  # become available. If the Future has already completed, the callback will
  # be called on the thread calling `onSuccess`, otherwise it will be called
  # from the thread on which the future has completed.
  #
  # @param [Block] observer the callback proc
  # @yieldparam [Object] value the exception raised during the Future's evaluation
  #
  def onFailure(&observer)
    @mutex.synchronize do
      if ready? && !@success
        observer.call(value(false)) rescue nil
      else
        add_callback(:failure, observer)
      end
    end
    self
  end

  #
  # Add a callback on a Future to receive the value if the Future has
  # completed successfully, or the Exception if it fails.
  #
  # This ensures that an observer receives the callback even after the value has
  # become available. If the Future has already completed, the callback will
  # be called on the thread calling `onSuccess`, otherwise it will be called
  # from the thread on which the future has completed.
  #
  # @param [Block] observer the callback proc
  # @yieldparam [Object] value the value or exception raised during the Future's evaluation
  # @yieldparam [Boolean] success true if the Future was successful, false if it failed
  #
  def onComplete(&observer)
    @mutex.synchronize do
      if ready?
        observer.call(value(false), @success) rescue nil
      else
        add_callback(:completion, observer)
      end
    end
    self
  end

  protected

  # all these methods must be called holding @mutex

  def add_callback(callback, observer)
    @_callbacks ||= {}
    (@_callbacks[callback] ||= []).push observer
  end

  def run_callback(callback, *args)
    return unless @_callbacks
    (@_callbacks[callback] || []).each do |cb|
      begin
        cb.call(*args)
      rescue
        ZeevexConcurrency.logger.warn "Callback in #{self} threw exception: #{$!}"
      end
    end
  end

  def fulfill_with_callbacks(result, success = true)
    fulfill_without_callbacks(result, success)
    run_callback(:completion, result, success)
    run_callback(success ? :success : :failure, result)
    # release callbacks to GC
    @_callbacks = {}
  end

end

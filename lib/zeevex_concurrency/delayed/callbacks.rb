#
# @abstract
#   This mixin implements the onSuccess, onFailure, and onComplete methods
#   from Scala Futures. More than one callback can be added to a {Delayed}
#   object which includes this mixin.
#
# Each on* method returns the Future upon which it was called, so calls can
# be chained.
#
# Callbacks may be called from the thread upon which the Delayed object was
# completed (i.e. the thread calling {Delayed#fulfill}), or if the Delayed
# object has already completed, from the thread which called {#onSuccess},
# {#onFailure}, or {#onComplete}.  In other words, you cannot assume anything
# about the calling thread. If you need specific thread semantics, your
# callback should arrange those immediately after being called.
#
# It is important that your callback be quick and never block. If it might
# block, then use a thread pool or Future to run it asynchronously.
#
# @example
#
#    my_future = Future.create do
#      some_calculation()
#    end.onSuccess do |result|
#      Future.create { sleep 5; puts "result was #{result}" }
#    end
#
# Each type of callback is currently called in order of registration, but you
# should not depend on that. All onComplete callbacks are executed before any
# onSuccess or onFailure callbacks are executed.
#
# When using Futures, you can use {ZeevexConcurrency::Future::AndThen#and_then} to
# arrange callbacks in an explicit sequence.  When using `and_then`, you don't
# need to worry about blocking, as each `and_then` callback is its own future.
#
# Requires that the Delayed object call {Delayed#fulfill} with the value
# when it completes. Also depends on the following methods and ivars:
#
# - #value(reraise=false)
# - #ready?
# - @success
# - @mutex - the mutex protecting most Delayed operations other than execution
#
# Callbacks are one-shot. If they are set for future execution, they are removed
# and made available to GC after they are called. If they are executed immediately,
# they are never stored in the object's @_callbacks variable.
#
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
  # @see Callbacks More information on callback registration and execution
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
  # @see Callbacks More information on callback registration and execution
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
  # @see Callbacks More information on callback registration and execution
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

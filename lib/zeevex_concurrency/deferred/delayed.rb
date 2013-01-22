require 'thread'
require 'countdownlatch'
require 'zeevex_concurrency'
require 'observer'

#
# base class for Promise, Future, etc. This should not be instantiated directly.
#
class ZeevexConcurrency::Delayed

  # @abstract Determine whether the Future is complete.
  #
  # @return [Boolean] true if the Future has completed or been cancelled
  def ready?; raise NotImplementedError; end

  module ConvenienceMethods
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

  def exception
    @exception
  end

  #
  # Check to see whether the Delayed object failed with an exception.
  #
  # @return [Boolean] true if the Delayed failed during evaluation
  #
  def exception?
    !! @exception
  end

  #
  # Check to see whether the Delayed object has already been evaluated.
  #
  # @return [Boolean] true if the Delayed was evaluated
  #
  def executed?
    @executed
  end

  #
  # Retrieve the value resulting from evaluation of the Delayed object.
  # If the Delayed has not completed yet, will block until it does.
  #
  # If the Delayed failed during evaluation, raises that exception.
  #
  # @param [Boolean] reraise if false, don't raise the exception from a failed
  #    evaluation. Just return the exception as a value.
  # @return [Object] the object resulting from the evaluation of the Delayed
  # @raise [StandardError] the exception
  #
  def value(reraise = true)
    result = _wait_for_value
    if @exception && reraise
      raise @exception
    elsif @exception
      @exception
    else
      result
    end
  end

  # Waits until the Delayed completed. If the Delayed has not completed yet,
  # will block until it does. If it has completed, returns immediately.
  #
  # If a timeout is supplied, will wait no longer tham `timeout` seconds.
  #
  # @param [Integer, nil] timeout if supplied and non-nil, the max seconds to wait
  # @return [Object] true on success, false on timeout
  #
  def wait(timeout = nil)
    Timeout::timeout(timeout) do
      value(false)
      true
    end
  rescue Timeout::Error
    false
  end

  protected

  def _initialize_delayed
    @mutex       = Mutex.new
    @exec_mutex  = Mutex.new
    @exception   = nil
    @result      = false
    @executed    = false
    @ready       = false
    @success     = false

    # from Cancellable
    @cancelled   = false

    # from Bindable
    @binding     = false
  end

  #
  # not MT-safe; only to be called from executor thread
  #
  def _execute(computation)
    raise "Already executed" if executed?
    raise ArgumentError, "Cannot execute without computation" unless computation
    @success = false
    begin
      result = computation.call
      @success = true
    rescue Exception
      @success = false
      @exception = $!
    end
    # run this separately so we can report exceptions in fulfill rather than capture them
    @mutex.synchronize do
      if @success
        fulfill(result)
      else
        smash(@exception)
      end
    end
    @executed = true
  rescue Exception
    puts "*** exception in fulfill: #{$!.inspect} #{$!.backtrace.join("\n")}***"
  ensure
    @executed = true
  end

  def fulfill(value, success = true)
    _fulfill(value, success)
  end

  #
  # not MT-safe; only to be called from executor thread
  #
  def smash(ex)
    @exception = ex
    fulfill ex, false
  end

  ###

  module Observable
    include ::Observable

    def self.included(base)
      base.class_eval do
        alias_method :add_observer_without_history, :add_observer
        alias_method :add_observer, :add_observer_with_history

        alias_method :fulfill_without_notification, :fulfill
        alias_method :fulfill, :fulfill_with_notification
      end
    end

    #
    # this ensures that an observer receives a value even after the value has
    # become available
    #
    # @private
    def add_observer_with_history(observer)
      @mutex.synchronize do
        if ready?
          # XXX: this is a bit hacky with both the functional and ivar access
          observer.send(:update, self, value(false), @success)
        else
          add_observer_without_history(observer)
        end
      end
    end

    # @private
    def fulfill_with_notification(result, success = true)
      fulfill_without_notification(result, success)
      _notify_and_remove_observers(result, success)
    end

    protected

    def _notify_and_remove_observers(result, success)
      changed
      begin
        notify_observers(self, result, success)
        delete_observers
      rescue Exception
        puts "Exception in notifying observers: #{$!.inspect} #{$!.backtrace.join("\n")}"
      end
    end
  end

  module Callbacks
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

  module LatchBased
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

  module Bindable
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

  module Cancellable
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

  module Dataflowable
    def self.included(base)
      require 'zeevex_concurrency/deferred/dataflow'
    end

    #
    # Wraps a Delayed object with a transparent proxy to the result of the
    # Delayed object.  In other words, it will proxy messages from the Dataflow
    # object to whatever result a Future yields. It will block the first time
    # such a message is sent if the Future is not yet ready.
    #
    # If the Future yields an exception, any message sent to the Dataflow variable
    # will raise that exception.
    #
    # @return [Dataflow] a dataflow-style deferred value
    #
    def to_dataflow
      ZeevexConcurrency::Dataflow.new(self)
    end
  end

  module Multiplexing
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

  module ForEach
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

  class CancelledException < StandardError; end
end

module ZeevexConcurrency
  extend(ZeevexConcurrency::Delayed::ConvenienceMethods)
end

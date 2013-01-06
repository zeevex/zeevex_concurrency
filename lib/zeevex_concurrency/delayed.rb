require 'thread'
require 'countdownlatch'

#
# base class for Promise, Future, etc.
#
class ZeevexConcurrency::Delayed

  module ConvenienceMethods
    def future(*args, &block)
      ZeevexConcurrency::Future.__send__(:create, *args, &block)
    end

    def promise(*args, &block)
      ZeevexConcurrency::Promise.__send__(:create, *args, &block)
    end

    def delay(*args, &block)
      ZeevexConcurrency::Delay.__send__(:create, *args, &block)
    end

    def delayed?(obj)
      obj.is_a?(ZeevexConcurrency::Delayed)
    end

    def delay?(obj)
      obj.is_a?(ZeevexConcurrency::Delay)
    end

    def promise?(obj)
      obj.is_a?(ZeevexConcurrency::Promise)
    end

    def future?(obj)
      obj.is_a?(ZeevexConcurrency::Future)
    end
  end

  def exception
    @exception
  end

  def exception?
    !! @exception
  end

  def executed?
    @executed
  end

  def value(reraise = true)
    @mutex.synchronize do
      unless @done
        @result = _wait_for_value
        @done   = true
      end
    end
    if @exception && reraise
      raise @exception
    else
      @result
    end
  end

  def wait(timeout = nil)
    Timeout::timeout(timeout) do
      value(false)
      true
    end
  rescue Timeout::Error
    false
  end

  def set_result(&block)
    @exec_mutex.synchronize do
      raise ArgumentError, "Must supply block" unless block_given?
      raise ArgumentError, "Already supplied block" if bound?
      raise ArgumentError, "Promise already executed" if executed?

      _execute(block)
    end
  end

  protected

  #
  # not MT-safe; only to be called from executor thread
  #
  def _execute(computation)
    raise "Already executed" if executed?
    raise ArgumentError, "Cannot execute without computation" unless computation
    success = false
    begin
      result = computation.call
      success = true
    rescue Exception
      _smash($!)
    end
    @executed = true
    # run this separately so we can report exceptions in _fulfill rather than capture them
    _fulfill_and_notify(result) if (success)
  rescue Exception
    puts "*** exception in _fulfill: #{$!.inspect} ***"
  ensure
    @executed = true
  end

  def _fulfill_and_notify(value, success = true)
    _fulfill(value, success)
    if respond_to?(:notify_observers)
      changed
      begin
        notify_observers(self, value, success)
      rescue Exception
        puts "Exception in notifying observers: #{$!.inspect}"
      end
    end
  end
  #
  # not MT-safe; only to be called from executor thread
  #
  def _smash(ex)
    @exception = ex
    _fulfill_and_notify ex, false
  end

  ###

  module LatchBased
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
      @_latch.countdown!
    end

    def _wait_for_value
      @_latch.wait
      @result
    end
  end

  module QueueBased
    def ready?
      @exec_mutex.synchronize do
        @queue.size > 0 || @executed
      end
    end

    protected

    def _initialize_queue
      @queue = Queue.new
    end

    def _fulfill(value, success = true)
      @queue << value
    end

    def _wait_for_value
      @queue.pop
    end
  end

  module Bindable
    def bound?
      !! @binding
    end

    def binding
      @binding
    end

    def bind(proccy = nil, &block)
      raise "Already bound" if bound?
      if proccy && block
        raise ArgumentError, "must supply a callable OR a block or neither, but not both"
      end
      raise ArgumentError, "Must provide computation as proc or block" unless (proccy || block)
      @binding = proccy || block
    end

    def execute
      @exec_mutex.synchronize do
        return if executed?
        return if respond_to?(:cancelled?) && cancelled?
        _execute(binding)
      end
    end

    def call
      execute
    end
  end

  module Cancellable
    def cancelled?
      @cancelled
    end

    def cancel
      @exec_mutex.synchronize do
        return false if executed?
        return true  if cancelled?
        @cancelled = true
        _smash CancelledException.new
        true
      end
    end

    def ready?
      cancelled? || super
    end
  end

  class CancelledException < StandardError; end
end

module ZeevexConcurrency
  extend(ZeevexConcurrency::Delayed::ConvenienceMethods)
end

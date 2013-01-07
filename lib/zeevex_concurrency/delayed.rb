require 'thread'
require 'countdownlatch'
require 'zeevex_concurrency'
require 'observer'
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
    @success = false
    begin
      result = computation.call
      @success = true
    rescue Exception
      smash($!)
    end
    @executed = true
    # run this separately so we can report exceptions in fulfill rather than capture them
    fulfill(result) if (@success)
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
    def add_observer_with_history(observer)
      # we synchronize on exec_mutex to prevent races where the value arrives as we observe, so we
      # miss the update
      @exec_mutex.synchronize do
        if ready?
          # XXX: this is a bit hacky with both the functional and ivar access
          observer.send(:update, self, value(false), @success)
        else
          add_observer_without_history(observer)
        end
      end
    end

    def fulfill_with_notification(value, success = true)
      fulfill_without_notification(value, success)
      _notify_and_remove_observers(value, success)
    end

    protected

    def _notify_and_remove_observers(value, success)
      changed
      begin
        notify_observers(self, value, success)
        delete_observers
      rescue Exception
        puts "Exception in notifying observers: #{$!.inspect}"
      end
    end
  end

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
        smash CancelledException.new
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

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
    result = _wait_for_value
    if @exception && reraise
      raise @exception
    elsif @exception
      @exception
    else
      result
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
      @ready  = true
      @_latch.countdown!
    end

    def _wait_for_value
      @_latch.wait
      @result
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

  module Dataflowable
    def self.included(base)
      require 'zeevex_concurrency/dataflow'
    end
    def to_dataflow
      ZeevexConcurrency::Dataflow.new(self)
    end
  end

  class CancelledException < StandardError; end
end

module ZeevexConcurrency
  extend(ZeevexConcurrency::Delayed::ConvenienceMethods)
end

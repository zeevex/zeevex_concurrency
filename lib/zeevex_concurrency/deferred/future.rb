require 'timeout'
require 'zeevex_concurrency'
require 'zeevex_concurrency/delayed'
require 'zeevex_concurrency/delayed/bindable'
require 'zeevex_concurrency/delayed/latch_based'
require 'zeevex_concurrency/delayed/cancellable'
require 'zeevex_concurrency/delayed/observable'
require 'zeevex_concurrency/delayed/callbacks'
require 'zeevex_concurrency/delayed/dataflowable'
require 'zeevex_concurrency/delayed/multiplexing'
require 'zeevex_concurrency/delayed/for_each'

require 'zeevex_concurrency/executors/event_loop'
require 'zeevex_concurrency/executors/thread_pool'

#
# A Future is a deferred computation which is intended to be executed asynchronously on
# another thread. It provides facilities for:
#
# - Blocking until the Future has completed
# - Polling for completion
# - Callbacks upon completion (both Observable and Scala style)
# - Blocking waits from multiple "clients"
# - Functional transformations into other Futures a la Scala
# - Transformation into an Oz-style Dataflow variable
# - 'select' style waiting on multiple Futures through Multiplexing
# - Cancelling outstanding Futures
# - Multiple worker pools
#
# The Future class creates a default process-wide pool of worker threads to use for processing
# Futures. Each Future may also be enqueued on a specific pool via options to the
# {Future.create} method or via a dynamic scope created via {Future.with_worker_pool}.
#
class ZeevexConcurrency::Future < ZeevexConcurrency::Delayed
  include ZeevexConcurrency::Delayed::Bindable
  include ZeevexConcurrency::Delayed::LatchBased
  include ZeevexConcurrency::Delayed::Cancellable
  include ZeevexConcurrency::Delayed::Observable
  include ZeevexConcurrency::Delayed::Callbacks
  include ZeevexConcurrency::Delayed::Dataflowable
  include ZeevexConcurrency::Delayed::Multiplexing
  include ZeevexConcurrency::Delayed::ForEach

  @@worker_pool = nil

  #
  # Create a new future. Unlike Future.create, a Future created
  # with Future.new is *not* automatically enqueued for execution.
  #
  # @param [Proc] computation a proc which will be executed to yield the Future's result
  # @param [Hash] options a hash of options
  # @option options [ZeevexConcurrency::ThreadPool::Abstract] :observers an observer object or list of objects which
  #    have an #update method - this functions in the style of the standard Observable system.
  # @param [Block] block if callable is nil, this block will be used instead
  #
  # @see create
  #
  def initialize(computation = nil, options = {}, &block)
    raise ArgumentError, "Must provide computation or block for a future" unless (computation || block)

    _initialize_delayed
    _initialize_latch

    # has to happen after exec_mutex initialized
    bind(computation, &block) if (computation || block)

    Array(options.delete(:observer) || options.delete(:observers)).each do |observer|
      add_observer observer
    end
  end

  #
  # Stop the current in-scope Future worker pool.
  #
  def self.shutdown
    self.worker_pool.stop
  end

  #
  # Create and enqueue a new future onto a worker pool.
  #
  # @param [Proc] callable a proc which will be executed to yield the Future's result
  # @param [Hash] options a hash of options
  # @option options [ZeevexConcurrency::ThreadPool::Abstract] :executor the executor to use
  # @option options [ZeevexConcurrency::ThreadPool::Abstract] :event_loop a synonym for :executor
  # @option options [ZeevexConcurrency::ThreadPool::Abstract] :observers an observer object or list of objects which
  #    have an #update method - this functions in the style of the standard Observable system.
  # @param [Block] block if callable is nil, this block will be used instead
  #
  # @see {Future#initialize}
  # @see {Observable}
  #
  def self.create(callable=nil, options = {}, &block)
    nfuture = ZeevexConcurrency::Future.new(callable, options, &block)
    (options.delete(:event_loop) || options.delete(:executor) || worker_pool).enqueue nfuture

    nfuture
  end

  #
  # Sets the global process-wide default worker pool.
  #
  # @return [ZeevexConcurrency::ThreadPool::Abstract] the in-scope worker pool for newly
  #   created Futures. Will be the thread-local pool if one is in scope; otherwise it's
  #   the process-wide pool.
  #
  def self.worker_pool
    Thread.current[:_future_worker_pool] || @@worker_pool
  end

  #
  # Sets the global process-wide default worker pool.
  #
  # @param [ZeevexConcurrency::ThreadPool::Abstract] pool a pool to use
  #
  def self.global_worker_pool=(pool)
    check_pool pool
    old_pool = @@worker_pool
    @@worker_pool = pool_retain(pool)
    pool_release(old_pool)
  end

  #
  # Sets the default worker pool for Futures created from this thread
  #
  # @param [ZeevexConcurrency::ThreadPool::Abstract] pool a pool to use
  #
  def self.worker_pool=(pool)
    check_pool pool
    old_pool = Thread.current[:_future_worker_pool]
    Thread.current[:_future_worker_pool] = pool_retain(pool)
    pool_release(old_pool)
  end

  def self.pool_retain(pool)
    if pool && pool.respond_to?(:retain)
      pool.retain
    end
    pool
  end

  def self.pool_release(pool)
    if pool && pool.respond_to?(:release)
      pool.release
    end
    pool
  end

  def self.check_pool(pool)
    raise ArgumentError, "Pool must respond to :enqueue" unless pool.respond_to?(:enqueue)
  end

  class << self
    protected :pool_retain, :pool_release, :check_pool
  end

  #
  # Execute block with the Future worker pool set to `pool` for the duration of the block.
  # The setting is thread-local and functions as a dynamic scope; nested `with_worker_pool`
  # calls are allowed.
  #
  # @param [ZeevexConcurrency::ThreadPool::Abstract] pool the pool to use
  # @yield [] the block is executed with no arguments
  #
  def self.with_worker_pool(pool)
    old_pool = Thread.current[:_future_worker_pool]
    Thread.current[:_future_worker_pool] = pool_retain(pool)
    raise ArgumentError, "Must provide pool" unless pool && pool.respond_to?(:enqueue)
    yield
  ensure
    Thread.current[:_future_worker_pool] = old_pool
    pool_release(pool)
  end

  class << self
    alias_method :future, :create
  end


  module Map
    #
    # Projects the value of this future as a param into a block which is evaluated in
    # a new Future, and returns that new future.
    #
    # @yield [value] value the resulting value of this Future
    # @return [Future] the new Future
    #
    def map(&block)
      new_future = ZeevexConcurrency::Future.new {}
      self.onComplete do |val, success|
        new_future._map_completion(val, success, block)
      end
      new_future
    end

    protected

    def _map_completion(value, success, block)
      @binding = Proc.new do
        if success
          block.call value
        else
          raise value
        end
      end

      ZeevexConcurrency::Future.worker_pool.enqueue self
    end
  end

  module FlatMap
    #
    # Projects the value of this future as a param into a block which is evaluated in
    # a new Future, and returns that new future. The difference from #map is that
    # the value of this Future is assumed to be a Future, and it is the value from
    # *that* inner Future that is projected. Think of it as "flattening" two nested
    # futures into one before mapping.
    #
    # @yield [value] value the resulting value of this Future, "flattened"
    # @return [Future] the new Future
    #
    def flat_map(&block)
      map { |input| block.call(input).value }
    end
  end

  module AndThen
    #
    # Projects the value of this future as a param into a block which is evaluated
    # in a new Future. Unlike {Map#map}, however, the result of the resulting Future is
    # discarded. The created Future is used for its side effects, not its value.
    # This might be useful in logging, sequencing callbacks, etc.
    #
    # Think of it as {::Kernel#tap} for Futures.
    #
    # @yield [value] value the resulting value of this Future
    # @return [Future] the new Future - while returning a different object, it will
    #   have the same value as this Future
    #
    def and_then(&block)
      transform lambda { |result| block.call(result, true) rescue nil; result },
                lambda { |error|  block.call(error, false) rescue nil; error }
    end
  end

  module Fallback
    #
    # Returns a new Future such that, if this Future succeeds, the new Future will
    # have the same value as this one.
    #
    # If this Future fails, the new Future will have the result of the supplied block
    # which is executed in the future
    #
    # @return [Future] the new Future
    #
     def fallback_to(&block)
      new_future = ZeevexConcurrency::Future.new {}
      self.onComplete do |val, success|
        new_future._fallback_completion(val, success, block)
      end
      new_future
    end

    protected

    def _fallback_completion(value, success, block)
      @binding = Proc.new do
        if success
          value
        else
          block.call
        end
      end
      ZeevexConcurrency::Future.worker_pool.enqueue self
    end
  end

  module Transform
    #
    # Given two transformation functions of 1 argument each, this method will
    # yield a new Future which has the result of applying the appropriate function
    # to the result of this Future.
    #
    # If this Future is successful, result_proc is applied to the value of this Future.
    #
    # If this Future is unsuccessful, failure_proc is applied to the Exception
    # from this Future.
    #
    # @param [Proc] result_proc the proc which transforms a successful result
    # @param [Proc] failure_proc the proc which transforms a failure result (exception)
    # @return [Future] a Future which yields the transformed result of this Future
    #
    def transform(result_proc, failure_proc)
      unless result_proc && failure_proc
        raise ArgumentError, 'Must suppluy both success and failure transformer'
      end
      new_future = ZeevexConcurrency::Future.new {}
      self.onComplete do |val, success|
        new_future._transform_completion(val, success, result_proc, failure_proc)
      end
      new_future
    end

    protected

    def _transform_completion(value, success, result_proc, failure_proc)
      @binding = Proc.new do
        if success
          result_proc.call value
        else
          res = failure_proc.call value
          raise res if res.is_a?(Exception)
          res
        end
      end
      ZeevexConcurrency::Future.worker_pool.enqueue self
    end
  end

  module Filter
    #
    # Tests the value of this Future against a filter function. If the filter function
    # returns a truthy value, then the new Future has the same value as this Future. If
    # the filter function returns a falsy value, then the new Future will be a failed
    # future containing an IndexError exception.
    #
    # @param [Block] filter_proc A function of one argument which yields a truthy or falsy value
    # @return [Future] a new Future
    #
    def filter(&filter_proc)
      unless filter_proc
        raise ArgumentError, 'Must supply filter proc'
      end
      new_future = ZeevexConcurrency::Future.new {}
      self.onComplete do |val, success|
        new_future._filter_completion(val, success, filter_proc)
      end
      new_future
    end

    protected

    def _filter_completion(value, success, filter_proc)
      @binding = Proc.new do
        if success
          filter_proc.call(value) ? value : raise(IndexError, 'Future filter did not pass value')
        else
          raise value
        end
      end
      ZeevexConcurrency::Future.worker_pool.enqueue self
    end
  end

  include Map
  include FlatMap
  include Fallback
  include Transform
  include Filter
  include AndThen

  self.global_worker_pool = ZeevexConcurrency::ThreadPool::FixedPool.new
end

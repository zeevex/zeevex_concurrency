require 'timeout'
require 'zeevex_concurrency'
require 'zeevex_concurrency/deferred/delayed'
require 'zeevex_concurrency/executors/event_loop'
require 'zeevex_concurrency/executors/thread_pool'

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

  def self.shutdown
    self.worker_pool.stop
  end

  def self.create(callable=nil, options = {}, &block)
    nfuture = ZeevexConcurrency::Future.new(callable, options, &block)
    (options.delete(:event_loop) || options.delete(:executor) || worker_pool).enqueue nfuture

    nfuture
  end

  def self.worker_pool
    Thread.current[:_future_worker_pool] || @@worker_pool
  end

  #
  # Sets the global process-wide default worker pool
  #
  def self.global_worker_pool=(pool)
    old_pool = @@worker_pool
    @@worker_pool = pool_retain(pool)
    pool_release(old_pool)
  end

  #
  # Sets the default worker pool for Futures created from this thread
  #
  def self.worker_pool=(pool)
    old_pool = Thread.current[:_future_worker_pool]
    Thread.current[:_future_worker_pool] = pool_retain(pool)
    pool_release(old_pool)
  end

  def self.pool_retain(pool)
    if pool && pool.respond_to?(:retain)
      pool.retain
    end
  end

  def self.pool_release(pool)
    if pool && pool.respond_to?(:release)
      pool.release
    end
    pool
  end

  class << self
    protected :pool_retain, :pool_release
  end

  #
  # Execute block with the Future worker pool set to `pool`
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
    def flat_map(&block)
      map { |input| block.call(input).value }
    end
  end

  module AndThen
    def and_then(&block)
      transform lambda { |result| block.call(result, true) rescue nil; result },
                lambda { |error|  block.call(error, false) rescue nil; error }
    end
  end

  module Fallback
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

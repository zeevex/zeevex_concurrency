require 'zeevex_concurrency'
require 'zeevex_concurrency/deferred/future'
require 'zeevex_concurrency/executors/thread_pool'

module ZeevexConcurrency
  #
  # Map function across list in parallel using Futures.
  # This is about as non-lazy as you can get - more of a PoC than a serious implementation.
  # It's better off running a small number of lengthy IO-bound operations concurrently
  # than trying to parallelize the processing of a very long list. Especially on MRI / CRuby.
  #
  # Optional `concurrency` argument is interpreted thusly:
  #
  # positive integer::   use a new pool with up to that many threads (no more than length of list)
  # no / nil argument::  use a new pool with default number of threads (2 * cpu_count)
  # -1::                 use the default Future thread pool
  # 0 or INT_MAX::       use exactly as many threads as length of list (fully concurrent)
  # pool or event_loop:: use the provided executor
  #
  # @param [Enumerable] collection the collection to map over
  # @param [Integer, nil, ZeevexConcurrency::ThreadPool::Abstract] concurrency a thread pool spec
  # @param [Block] block the block to yield to for each element of the collection
  # @return [Array] the resulting collection - will be an Array no matter the source collection type
  #
  # @see ZeevexConcurrency.thread_pool_from_spec
  # @see Enumerable#pmap
  #
  def self.greedy_pmap(collection, concurrency = nil, &block)
    raise ArgumentError, "Requires collection" unless collection && collection.respond_to?(:map)
    raise ArgumentError, "Requires block"      if block.nil?
    pool = thread_pool_from_spec(concurrency, nil, collection.length)
    collection.map do |input|
      ZeevexConcurrency::Future.create(nil, :executor => pool) { block.call input }
    end.map(&:value)
  ensure
    pool.stop if pool
  end

  # Construct or return a thread pool matching `spec` argument, which is interpreted
  # thusly:
  #
  # positive integer::   use a new pool with up to that many threads (no more than bounded_size if supplied)
  # nil::                use a new pool with default number of threads (2 * cpu_count)
  # -1::                 use the default Future thread pool, or defpool if supplied
  # 0 or INT_MAX::       use exactly as many threads as bounded_size (fully concurrent)
  # pool or event_loop:: use the provided executor
  #
  # @param [Integer, nil, ZeevexConcurrency::ThreadPool::Abstract] spec 
  #   a thread pool spec as above
  # @param [nil, ZeevexConcurrency::ThreadPool::Abstract] defpool 
  #   the pool to use by default if `spec` == -1
  # @param [nil, Integer] bounded_size if provided, the max size the thread pool
  #   should reach; if nil may mean 2*CPUs
  #
  def self.thread_pool_from_spec(spec, defpool = nil, bounded_size = nil)
    case spec
    when 0
      ZeevexConcurrency::ThreadPool::FixedPool.new(bounded_size)
    when ZeevexConcurrency::ThreadPool::Abstract, ZeevexConcurrency::EventLoop
      spec
    when nil
      ZeevexConcurrency::ThreadPool::FixedPool.new
    when -1
      defpool || ZeevexConcurrency::Future.worker_pool
    when Integer
      ZeevexConcurrency::ThreadPool::FixedPool.new(bounded_size ? [spec, bounded_size].min : spec)
    else
      raise ArgumentError, "pool spec invalid: #{spec.inspect}"
    end
  end
end

module Enumerable
  #
  # Map function across list in parallel using Futures.
  # This is about as non-lazy as you can get - more of a PoC than a serious implementation.
  # It's better off running a small number of lengthy IO-bound operations concurrently
  # than trying to parallelize the processing of a very long list. Especially on MRI / CRuby.
  #
  # @param [Integer, nil, ZeevexConcurrency::ThreadPool::Abstract] concurrency a thread pool spec
  # @param [Block] block the block to yield to for each element of the collection
  # @return [Array] the resulting collection - will be an Array no matter the source collection type
  #
  # @see ZeevexConcurrency.greedy_pmap greedy_pmap - the method that's actually called
  # @see ZeevexConcurrency.thread_pool_from_spec thread_pool_from_spec - for possible values for `concurrency` param
  def pmap(concurrency = nil, &block)
    ZeevexConcurrency.greedy_pmap(self, concurrency, &block)
  end
end

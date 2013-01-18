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
  # positive integer:   use a new pool with up to that many threads (no more than length of list)
  # no / nil argument:  use a new pool with default number of threads (2 * cpu_count)
  # -1:                 use the default Future thread pool
  # 0 or INT_MAX:       use exactly as many threads as length of list (fully concurrent)
  # pool or event_loop: use the provided executor
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
  # positive integer:   use a new pool with up to that many threads (no more than bounded_size if supplied)
  # no / nil argument:  use a new pool with default number of threads (2 * cpu_count)
  # -1:                 use the default Future thread pool, or defpool if supplied
  # 0 or INT_MAX:       use exactly as many threads as bounded_size (fully concurrent)
  # pool or event_loop: use the provided executor
  #
  def self.thread_pool_from_spec(spec, defpool = nil, bounded_size = nil)
    defpool ||= ZeevexConcurrency::Future.worker_pool
    case spec
    when 0
      ZeevexConcurrency::ThreadPool::FixedPool.new(bounded_size)
    when ZeevexConcurrency::ThreadPool, ZeevexConcurrency::EventLoop
      spec
    when nil
      ZeevexConcurrency::ThreadPool::FixedPool.new
    when -1
      ZeevexConcurrency::Future.worker_pool
    when Integer
      ZeevexConcurrency::ThreadPool::FixedPool.new(bounded_size ? [spec, bounded_size].min : spec)
    else
      raise ArgumentError, "pool spec invalid: #{spec.inspect}"
    end
  end
end

module Enumerable
  def pmap(concurrency = nil, &block)
    ZeevexConcurrency.greedy_pmap(self, concurrency, &block)
  end
end

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
  include ZeevexConcurrency::Delayed::Map

  # @@worker_pool = ZeevexConcurrency::EventLoop.new
  @@worker_pool = ZeevexConcurrency::ThreadPool::FixedPool.new
  @@worker_pool.start

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
    (options.delete(:event_loop) || worker_pool).enqueue nfuture

    nfuture
  end

  def self.worker_pool
    @@worker_pool
  end

  def self.worker_pool=(pool)
    @@worker_pool = pool
  end

  class << self
    alias_method :future, :create
  end
end


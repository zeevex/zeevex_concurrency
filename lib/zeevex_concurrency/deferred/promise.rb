require 'timeout'
require 'zeevex_concurrency/delayed'
require 'zeevex_concurrency/delayed/bindable'
require 'zeevex_concurrency/delayed/latch_based'
require 'zeevex_concurrency/delayed/observable'
require 'zeevex_concurrency/delayed/callbacks'
require 'zeevex_concurrency/delayed/dataflowable'
require 'zeevex_concurrency/delayed/multiplexing'
require 'zeevex_concurrency/delayed/for_each'

class ZeevexConcurrency::Promise < ZeevexConcurrency::Delayed
  include ZeevexConcurrency::Delayed::Observable
  include ZeevexConcurrency::Delayed::Callbacks
  include ZeevexConcurrency::Delayed::Bindable
  include ZeevexConcurrency::Delayed::LatchBased
  include ZeevexConcurrency::Delayed::Dataflowable
  include ZeevexConcurrency::Delayed::Multiplexing
  include ZeevexConcurrency::Delayed::ForEach

  def initialize(computation = nil, options = {}, &block)

    _initialize_delayed
    _initialize_latch

    # has to happen after exec_mutex initialized
    bind(computation, &block) if (computation || block)

    Array(options.delete(:observer) || options.delete(:observers)).each do |observer|
      self.add_observer observer
    end
  end

  def self.create(callable = nil, options = {}, &block)
    return callable if callable && callable.is_a?(ZeevexConcurrency::Delayed)
    new(callable, options, &block)
  end

  def set_result(&block)
    @exec_mutex.synchronize do
      raise ArgumentError, "Must supply block" unless block_given?
      raise ArgumentError, "Already supplied block" if bound?
      raise ArgumentError, "Promise already executed" if executed?

      _execute(block)
    end
  end

  def <<(value)
    set_result { value }
  end
end

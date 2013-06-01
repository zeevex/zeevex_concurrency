require 'timeout'
require 'zeevex_concurrency/delayed'
require 'zeevex_concurrency/delayed/bindable'
require 'zeevex_concurrency/delayed/latch_based'
require 'zeevex_concurrency/delayed/observable'
require 'zeevex_concurrency/delayed/callbacks'
require 'zeevex_concurrency/delayed/dataflowable'
require 'zeevex_concurrency/delayed/multiplexing'
require 'zeevex_concurrency/delayed/for_each'

#
# A Promise is a handle to a result which is intended to be supplied asynchronously from
# another thread. It provides facilities for:
#
# - Blocking until the Promise has completed
# - Polling for completion
# - Callbacks upon completion (both Observable and Scala style)
# - Blocking waits from multiple "clients"
# - Transformation into an Oz-style Dataflow variable
# - 'select' style waiting on multiple Promises through Multiplexing
#
# Unlike Futures, Promises are not processed by a worker pool. Instead, their
# result values are provided explicitly from application code by calling the
# {Promise#set_result} method.
#
class ZeevexConcurrency::Promise < ZeevexConcurrency::Delayed
  include ZeevexConcurrency::Delayed::Observable
  include ZeevexConcurrency::Delayed::Callbacks
  include ZeevexConcurrency::Delayed::Bindable
  include ZeevexConcurrency::Delayed::LatchBased
  include ZeevexConcurrency::Delayed::Dataflowable
  include ZeevexConcurrency::Delayed::Multiplexing
  include ZeevexConcurrency::Delayed::ForEach

  #
  # Create a new Promise.
  #
  # @param [Proc] computation a proc which will be executed to yield the Promise's result. It is
  #     customary not to provide a computation to bind to the Promise, but rather to have app code
  #     simply set the result.
  # @param [Hash] options a hash of options
  # @option options [#update] :observers an observer object or list of objects which
  #    have an #update method - this functions in the style of the standard Observable system.
  # @param [Block] block if computation is nil, this block may be used instead. Again, it is customary not
  #    to supply one.
  #
  # @see create
  #
  def initialize(computation = nil, options = {}, &block)

    _initialize_delayed
    _initialize_latch

    # has to happen after exec_mutex initialized
    bind(computation, &block) if (computation || block)

    Array(options.delete(:observer) || options.delete(:observers)).each do |observer|
      self.add_observer observer
    end
  end

  #
  # Similar to {ZeevexConcurrency::Promise.new}
  #
  # @see initialize
  #
  def self.create(callable = nil, options = {}, &block)
    return callable if callable && callable.is_a?(ZeevexConcurrency::Delayed)
    new(callable, options, &block)
  end

  #
  # Sets the value of this Promise. This method should be called by the "Producer" end
  # of the promise with a block, and the result of the block will be delivered to all
  # "Consumers" of the Promise.
  #
  # @param [Block] block evaluated to produce the value or exception result
  # @yield evaluates the provided block without parameters
  # @yieldreturn [Object, Exception] the block should return a result on success, and
  #    raise an Exception on failure.
  #
  def set_result(&block)
    @exec_mutex.synchronize do
      raise ArgumentError, "Must supply block" unless block_given?
      raise ArgumentError, "Already supplied block" if bound?
      raise ArgumentError, "Promise already executed" if executed?

      _execute(block)
    end
  end

  #
  # Sets the value of this Promise. This method should be called by the "Producer" end
  # of the promise with a value, and that value will be delivered to all
  # "Consumers" of the Promise as a successful computation.
  #
  # @param [Object] value the value to deliver
  #
  def <<(value)
    set_result { value }
  end
end

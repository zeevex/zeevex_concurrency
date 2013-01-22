require 'thread'
require 'zeevex_concurrency'
require 'zeevex_concurrency/delayed'
require 'zeevex_concurrency/delayed/bindable'

#
# A Delay is a handle to a result which is intended to be evaluated later, if needed. The
# computation to be delayed is provided at creation time, and is guaranteed to be evaluated
# at most once.
#
# Unlike Promises and Futures, the computation is executed on the thread of the first
# attempt to retrieve the Delay's value. Other threads attempting to retrieve that
# result will block until the computation completes.
#
# Delays are not really designed for concurrency, though they are thread-safe. Their
# primary purpose is laziness.
#
class ZeevexConcurrency::Delay < ZeevexConcurrency::Delayed
  include ZeevexConcurrency::Delayed::Bindable

  #
  # Create a new Delay.
  #
  # @param [Proc] computation a proc which will be executed to yield the Delay's result.
  # @param [Hash] options a hash of options
  # @param [Block] block if computation is nil, this block may be used instead.
  #
  # One of `computation` or `block` is required.
  #
  # @see create
  #
  def initialize(computation = nil, options = {}, &block)
    raise ArgumentError, "Must provide computation or block for a future" unless (computation || block)

    _initialize_delayed
    @fulfilled_value = nil
 
    # has to happen after exec_mutex initialized
    bind(computation, &block)
  end

  #
  # Similar to {ZeevexConcurrency::Delay.new}
  #
  # @see initialize
  #
  def self.create(callable = nil, options = {}, &block)
    return callable if callable && callable.is_a?(ZeevexConcurrency::Delayed)
    new(callable, options, &block)
  end

  def wait(timeout = nil)
    true
  end

  def ready?
    true
  end

  protected

  def _fulfill(value, success = true)
    @fulfilled_value = value
  end

  def _wait_for_value
    @exec_mutex.synchronize do
      _execute(binding) unless @executed
      should_execute = !@executing
    end

    @fulfilled_value
  end
end

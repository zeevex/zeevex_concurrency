require 'thread'
require 'zeevex_concurrency'
require 'zeevex_concurrency/deferred/delayed'

class ZeevexConcurrency::Delay < ZeevexConcurrency::Delayed
  include ZeevexConcurrency::Delayed::Bindable

  def initialize(computation = nil, options = {}, &block)
    raise ArgumentError, "Must provide computation or block for a future" unless (computation || block)

    _initialize_delayed
    @fulfilled_value = nil
 
    # has to happen after exec_mutex initialized
    bind(computation, &block)
  end

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
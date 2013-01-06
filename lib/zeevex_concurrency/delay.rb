require 'observer'
require 'thread'
require 'zeevex_concurrency/delayed'

class ZeevexConcurrency::Delay < ZeevexConcurrency::Delayed
  include Observable
  include ZeevexConcurrency::Delayed::Bindable

  def initialize(computation = nil, options = {}, &block)
    raise ArgumentError, "Must provide computation or block for a future" unless (computation || block)

    @mutex       = Mutex.new
    @exec_mutex  = Mutex.new
    @exception   = nil
    @done        = false
    @result      = false
    @executed    = false

    # has to happen after exec_mutex initialized
    bind(computation, &block)

    Array(options.delete(:observer) || options.delete(:observers)).each do |observer|
      add_observer observer
    end
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
    _execute(binding)
    @fulfilled_value
  end
end

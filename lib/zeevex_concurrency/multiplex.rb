require 'timeout'
require 'observer'
require 'countdownlatch'
require 'zeevex_concurrency/delayed'

class ZeevexConcurrency::Multiplex
  include Observable

  def initialize(dependencies, count = nil, options = {})
    raise ArgumentError, "Must provide a list of dependencies" unless dependencies && !dependencies.empty?

    @mutex        = Mutex.new
    @dependencies = dependencies.clone.freeze
    @waiting      = dependencies.clone
    @complete     = []

    @latch        = CountDownLatch.new(count || @dependencies.length)

    Array(options.delete(:observer) || options.delete(:observers)).each do |observer|
      add_observer observer
    end

    @dependencies.each do |dep|
      dep.add_observer self
    end
  end

  def ready?
    @latch.count == 0
  end

  def wait(timeout = nil)
    @latch.wait(timeout)
  end

  def value(timeout = nil)
    wait(timeout)
    @complete.dup
  end

  def dependencies
    @dependencies
  end

  def complete
    @complete.clone
  end

  def waiting
    @waiting.clone
  end

  # callback from notifiers
  def update(source, *args)
    @mutex.synchronize do
      if @waiting.delete(source)
        @complete << source
        @latch.countdown!

        do_complete if @count == 0
      end
    end
  end

  def add_observer_with_history(observer)
    @mutex.synchronize do
      add_observer_without_history observer
      if ready?
        do_notify_observers
      end
    end
  end

  alias_method :add_observer_without_history, :add_observer
  alias_method :add_observer, :add_observer_with_history

  protected

  def do_complete
    @waiting.freeze
    @complete.freeze
    do_notify_observers
  end

  def do_notify_observers
    changed
    notify_observers @complete
    delete_observers
  end

end


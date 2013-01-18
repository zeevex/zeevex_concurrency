require 'timeout'
require 'observer'
require 'countdownlatch'
require 'zeevex_concurrency'
require 'zeevex_concurrency/deferred/delayed'

class ZeevexConcurrency::Multiplex
  include Observable

  def initialize(dependencies, count = nil, options = {})
    raise ArgumentError, "Must provide a list of dependencies" unless dependencies && !dependencies.empty?

    @mutex        = Mutex.new
    @dependencies = dependencies.clone.freeze
    @waiting      = dependencies.clone
    @complete     = []
    @result       = nil

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
    @result.dup
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
        do_complete if @latch.count == 1

        # release waiters
        @latch.countdown!
      else
        STDERR.puts "Received update from non-waiting source: #{source.inspect}"
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
    @result = @complete.dup.freeze
    do_notify_observers
  end

  def do_notify_observers
    changed
    notify_observers self, @complete.clone
    delete_observers
  end

end

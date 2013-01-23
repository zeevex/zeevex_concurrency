require 'thread'
require 'zeevex_concurrency'
require 'zeevex_concurrency/deferred/promise'

module ZeevexConcurrency
  #
  # An EventLoop used one thread to perform a series of computations provided
  # to it via the #enqueue method in strict submission order.
  #
  class EventLoop
    #
    # Create a new thread EventLoop
    #
    # @param [Hash] options a hash of options
    # @option options [Queue] :queue the queue to use for a newly created EventLoop
    # @option options [Mutex, Monitor] :mutex the mutex to use for internal synchronization
    #
    def initialize(options = {})
      @options = options
      @mutex   = options.delete(:mutex) || Mutex.new
      @queue   = options.delete(:queue) || Queue.new
      @state   = :stopped
    end

    #
    # Check whether this event loop is running.
    #
    # @return [Boolean]
    #
    def running?
      @state == :started
    end

    # Start processing jobs. Creates processor thread.
    #
    def start
      return unless @state == :stopped
      @stop_requested = false
      @thread = Thread.new do
        process
      end

      @state = :started
    end

    #
    # Stop processing new jobs. Closes down the processor thread, though
    # that may not be possible until it completes the currently executing
    # job.
    #
    def stop
      return unless @state == :started
      enqueue { @stop_requested = true }
      unless @thread.join(5)
        # TODO: use Platform to test for this
        unless defined?(JRuby)
          Thread.new { @thread.kill; @thread.join(0) }
        end
      end

      @thread = nil
      @state = :stopped
    end

    #
    # Enqueue any callable object (including a Promise or Future or other Delayed class) to the event loop
    # and return a Delayed object which can be used to fetch the return value.
    #
    # Strictly obeys ordering.
    #
    # @param [Future, Promise, Proc, #call, nil] callable any object which responds to #call and returns a value
    # @param [Block] block if no callable is supplied, a block is used as the computation
    # @yield no arguments are passed to the block or proc
    # @yieldreturn [Object] the result of the computation.
    # @return [Promise, Future] a Promise which will contain the result of the callable after it runs.
    #    if a Future is enqueued, a Future might be returned instead.
    # @raise ArgumentError if neither a callable nor block is supplied
    #
    def enqueue(callable = nil, &block)
      to_run = callable || block
      raise ArgumentError, "Must provide proc or block arg" unless to_run

      to_run = ZeevexConcurrency::Promise.new(to_run) unless to_run.is_a?(ZeevexConcurrency::Delayed)
      @queue << to_run
      to_run
    end

    #
    # Enqueue a callable.
    #
    # @see enqueue
    def <<(callable)
      enqueue(callable)
    end

    #
    # flush any queued but un-executed tasks
    #
    def flush
      @queue.clear
    end

    #
    # how many tasks are waiting to execute
    #
    # @return [Integer] the number of tasks waiting
    #
    def backlog
      @queue.size
    end

    # stop, flush, and restart the EventLoop
    def reset
      stop
      flush
      start
    end

    #
    # Check whether the method was called from code executing on the event loop's thread
    #
    # @return [Boolean] true if caller is running on event loop thread
    #
    def in_event_loop?
      Thread.current.object_id == @thread.object_id
    end

    #
    # Runs a computation on the event loop. Does not deadlock if currently on the event loop, but
    # will not preserve ordering either - it runs the computation immediately despite other events
    # in the queue.
    #
    # @param [Future, Promise, Proc, #call, nil] callable any object which responds to #call and returns a value
    # @param [Block] block if no callable is supplied, a block is used as the computation
    # @yield no arguments are passed to the block or proc
    # @yieldreturn [Object] the result of the computation.
    # @return [Promise, Future] a Promise which will contain the result of the callable after it runs.
    #    if a Future is enqueued, a Future might be returned instead.
    # @raise ArgumentError if neither a callable nor block is supplied
    #
    # @see enqueue
    #
    def on_event_loop(callable = nil, &block)
      return unless callable || block_given?
      promise = (callable && callable.is_a?(ZeevexConcurrency::Delayed)) ?
                 callable :
                 ZeevexConcurrency::Promise.create(callable, &block)
      if in_event_loop?
        promise.call
        promise
      else
        enqueue promise, &block
      end
    end

    #
    # Returns the value from the computation rather than a Promise.  Has similar semantics to
    # `on_event_loop` - if this is called from the event loop, it just executes the
    # computation synchronously ahead of any other queued computations
    #
    # @param [Future, Promise, Proc, #call, nil] callable any object which responds to #call and returns a value
    # @param [Block] block if no callable is supplied, a block is used as the computation
    # @yield no arguments are passed to the block or proc
    # @yieldreturn [Object] the result of the computation.
    # @return [Object] the result of the computation, if successful
    # @raise ArgumentError if neither a callable nor block is supplied
    # @raise Exception if the result of the computation is an error, it will be raised
    #
    # @see enqueue
    #
    def run_and_wait(callable = nil, &block)
      promise = on_event_loop(callable, &block)
      promise.value
    end

    protected

    def process
      while !@stop_requested
        begin
          process_one
        rescue
          ZeevexConcurrency.logger.error %{Exception caught in event loop: #{$!.inspect}: #{$!.backtrace.join("\n")}}
        end
      end
    end

    def process_one
      @queue.pop.call
    end

    public

    #
    # event loop which throws away all events without running, returning nil from all promises
    #
    class Null
      def initialize(options = {}); end
      def start; end
      def stop; end
      def enqueue(callable = nil, &block)
        to_run = ZeevexConcurrency::Promise.new unless to_run.is_a?(ZeevexConcurrency::Delayed)
        to_run.set_result { nil }
        to_run
      end
      def in_event_loop?; false; end
      def on_event_loop(runnable = nil, &block)
        enqueue(runnable, &block)
      end
    end

    #
    # event loop which runs all events synchronously when enqueued on the calling thread.
    # This is primarily intended for testing.
    #
    class Inline < ZeevexConcurrency::EventLoop
      def start; end
      def stop; end
      def enqueue(callable = nil, &block)
        res = super
        process_one
        res
      end
      def in_event_loop?; true; end
    end

  end
end

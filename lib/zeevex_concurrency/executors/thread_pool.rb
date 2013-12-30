require 'zeevex_concurrency'
require 'zeevex_concurrency/executors/event_loop'
require 'zeevex_concurrency/util/refcount'
require 'zeevex_concurrency/util/platform'
require 'countdownlatch'
require 'thread'
require 'atomic'

#
# A ThreadPool manages zero or more threads to use in performing computations provided
# to it via the #enqueue method.
#
# A variety of ThreadPool implementations is provided.
#
module ZeevexConcurrency::ThreadPool
  class Abstract
    include ZeevexConcurrency::Util::Refcount

    def initialize(*args)
      _initialize_refcount
    end

    def destroy
      stop
    end
  end

  module Stubs
    #
    # Determine whether all the threads in the pool are occupied with computations.
    # If this is true, there may be some delay in executing new jobs submitted via
    # enqueue.
    #
    # @return [Boolean] true if all the threads in the pool are busy
    # @abstract
    #
    def busy?
      free_count == 0
    end

    #
    # Retrieve the number of currently managed threads; may be -1 if unimplemented
    # or not relevant
    #
    # @return [Integer] the number of currently managed threads
    # @abstract
    #
    def worker_count
      -1
    end

    #
    # Retrieve the number of currently executing threads; may be -1 if unimplemented
    # or not relevant
    #
    # @return [Integer] the number of busy threads
    # @abstract
    #
    def busy_count
      -1
    end

    #
    # Retrieve the number of currently managed threads which are not busy;
    # may be -1 if unimplemented or not relevant. If it returns a
    # non-negative number, this indicates how many jobs will begin
    # execution immediately if enqueued.
    #
    # @return [Integer] the number of currently managed threads
    #
    def free_count
      (worker_count - busy_count)
    end

    #
    # flush any queued but un-executed tasks
    #
    # @abstract
    def flush
      true
    end

    #
    # Returns after all currently enqueued tasks complete - does not guarantee
    # that tasks are not enqueued while the calling thread is waiting. If that
    #
    # @note This currently only works on single-threaded pools. The current
    #   implementation will return after all currently enqueued tasks have
    #   BEGUN execution, but not completed.
    #
    # XXX: this method is broken
    #
    def join
      latch = CountDownLatch.new(1)
      enqueue do
        latch.countdown!
      end
      latch.wait
      true
    end

    #
    # Returns after all currently enqueued tasks have at least begun execution.
    # Does not guarantee that tasks are not enqueued while the calling thread is waiting.
    #
    def mark
      latch = CountDownLatch.new(1)
      enqueue do
        latch.countdown!
      end
      latch.wait
      true
    end

    #
    # how many tasks are waiting to execute
    #
    # @return [Integer] the number of tasks waiting
    # @abstract
    #
    def backlog
      0
    end

    #
    # Start processing jobs. Creates threads if appropriate.
    # @abstract
    #
    def start; end

    #
    # Stop processing new jobs. Closes down threads if appropriate, though
    # that may not be possible until they complete their currently executing
    # job.
    #
    # It is not defined whether a thread pool can be re-started once stopped.
    #
    # @abstract
    #
    def stop; end

    protected

    def _check_args(*args)
      args = args.reject {|f| f.nil? || !f.respond_to?(:call) }
      raise ArgumentError, "Must supply a callable or block" unless args.length == 1
      args[0]
    end
  end

  #
  # Uses a single-threaded event loop to process jobs.
  #
  # @see EventLoop
  #
  class EventLoopAdapter < Abstract
    include Stubs

    #
    # Create a new thread pool using an EventLoop to perform the actual execution.
    # If `loop` is nil, create an EventLoop.
    #
    # @param [EventLoop, nil] loop the event_loop to use. Will call #start on it.
    # @param [Hash] options a hash of options
    # @option options [Queue] :queue the queue to use for a newly created EventLoop
    #
    #
    def initialize(loop = nil, options = {})
      super
      @loop ||= ZeevexConcurrency::EventLoop.new(:queue => options.delete(:queue))
      start
    end

    # Start processing jobs. Creates threads if appropriate.
    #
    def start
      @loop.start
    end

    #
    # Stop processing new jobs. Closes down threads if appropriate, though
    # that may not be possible until they complete their currently executing
    # job.
    #
    # It is not defined whether a thread pool can be re-started once stopped.
    #
    def stop
      @loop.stop
    end

    #
    # Submit a job for processing in this thread pool.
    #
    # @param [Proc, #call, nil] callable any object which responds to #call and returns a value
    # @param [Block] block if no callable is supplied, a block is used as the computation
    # @return undefined
    # @yield no arguments are passed to the block or proc
    # @yieldreturn [Object] the result of the computation
    #
    def enqueue(callable = nil, &block)
      if @stop_requested
        return false
      end
      @loop.enqueue _check_args(callable, block)
    end

    #
    # flush any queued but un-executed tasks
    #
    def flush
      @loop.flush
      true
    end

    #
    # how many tasks are waiting to execute
    #
    # @return [Integer] the number of tasks waiting
    #
    def backlog
      @loop.backlog
    end
  end

  #
  # Run job semi-synchronously (on a separate thread, but block on it)
  # We use a separate thread
  #
  class InlineThreadPool < Abstract
    include Stubs

    def initialize
      super
      start
    end

    # Start processing jobs. 
    #
    def start
      @started = true
    end

    #
    # Stop processing new jobs. 
    #
    def stop
      @started = false
    end

    #
    # Returns after all currently enqueued tasks complete
    #
    def join
      true
    end

    #
    # Submit a job for processing in this thread pool.
    #
    # @param [Proc, #call, nil] callable any object which responds to #call and returns a value
    # @param [Block] block if no callable is supplied, a block is used as the computation
    # @yield no arguments are passed to the block or proc
    # @yieldreturn [Object] the result of the computation
    #
    def enqueue(callable = nil, &block)
      raise "Must be started" unless @started
      callable = _check_args(callable, block)
      thr = Thread.new do
        callable.call
      end
      thr.join
    end
  end

  #
  # Launch a concurrent thread for every new task enqueued
  #
  class ThreadPerJobPool < Abstract
    include Stubs

    #
    # Creates a new ThreadPerJobPool. Takes no arguments or options.
    #
    def initialize
      super
      @mutex      = Mutex.new
      @group      = ThreadGroup.new
      @busy_count = Atomic.new(0)

      start
    end

    #
    # Submit a job for processing in this thread pool.
    #
    # @param [Proc, #call, nil] callable any object which responds to #call and returns a value
    # @param [Block] block if no callable is supplied, a block is used as the computation
    # @yield no arguments are passed to the block or proc
    # @yieldreturn [Object] the result of the computation
    #
    def enqueue(callable = nil, &block)
      raise "Must be started" unless @started
      callable = _check_args(callable, block)
      thr = Thread.new do
        @busy_count.update {|x| x + 1}
        callable.call
        @busy_count.update {|x| x - 1}
      end
      @mutex.synchronize do
        @group.add(thr)
      end
    end

    #
    # Start processing jobs
    #
    def start
      @started = true
    end

    #
    # Returns after all currently enqueued tasks complete - does not guarantee
    # that tasks are not enqueued while the calling thread is waiting.
    #
    def join
      thread_list = @mutex.synchronize do
        @group.list.dup
      end

      thread_list.dup.each do |thr|
        thr.join
      end
      true
    end

    #
    # Stop processing new jobs. Closes down threads if appropriate, though
    # that may not be possible until they complete their currently executing
    # job.
    #
    def stop
      @mutex.synchronize do
        return unless @started

        @group.list.dup.each do |thr|
          thr.kill
        end

        @started = false
        @busy_count.set 0
      end
    end

    #
    # Retrieve the number of currently executing threads; may be -1 if unimplemented
    # or not relevant
    #
    # @return [Integer] the number of busy threads
    #
    def busy_count
      @busy_count.value
    end

    #
    # Determine whether all the threads in the pool are occupied with computations.
    # If this is true, there may be some delay in executing new jobs submitted via
    # enqueue.
    #
    # @return [Boolean] true if all the threads in the pool are busy
    #
    def busy?
      false
    end

    alias_method :worker_count, :busy_count
  end

  #
  # Use a fixed pool of N threads to process jobs
  #
  class FixedPool < Abstract
    include Stubs

    #
    # Create a new FixedPool object with a specified number of threads.
    #
    # @param [Integer, -1] count create `count` threads to process jobs. if
    #   absent or -1, use 2 * the number of CPUs in the host.
    # @param [Hash] options a hash of options
    # @option options [Queue] :queue the queue to use for job backlog
    #
    def initialize(count = -1, options = {})
      super
      if count.nil? || count == -1
        count = ZeevexConcurrency::ThreadPool.cpu_count * 2
      end
      @count = count
      @queue = options.delete(:queue) || Queue.new
      @mutex = Mutex.new
      @group = ThreadGroup.new
      @busy_count = Atomic.new(0)

      start
    end

    #
    # Submit a job for processing in this thread pool.
    #
    # @param [Proc, #call, nil] callable any object which responds to #call and returns a value
    # @param [Block] block if no callable is supplied, a block is used as the computation
    # @yield no arguments are passed to the block or proc
    # @yieldreturn [Object] the result of the computation
    #
    def enqueue(callable = nil, &block)
      if @stop_requested
        return false
      end
      @queue << _check_args(callable, block)
    end

    # Start processing jobs. Creates `count` worker threads when called.
    def start
      @mutex.synchronize do
        return if @started

        @stop_requested = false

        @count.times do
          thr = Thread.new(@queue) do
            while !@stop_requested
              begin
                work = @queue.pop

                # notify that this thread is stopping and wait for the signal to continue
                if work.is_a?(HaltObject)
                  # puts "thread #{Thread.current.object_id} obeying halt"
                  work.halt!
                  continue
                end

                _start_work
                work.call
                _end_work
              rescue Exception
                ZeevexConcurrency.logger.error %{Exception caught in thread pool: #{$!.inspect}: #{$!.backtrace.join("\n")}}
              end
            end
          end
          @group.add(thr)
        end

        @started = true
      end
    end

    #
    # Stop processing new jobs. Closes down threads, though
    # that may not be possible until they complete their currently executing
    # job.
    #
    def stop
      @mutex.synchronize do
        return unless @started
        @stop_requested = true

        @queue.clear
        halt_n_times(@count)

        # XXX: this is a temp hack and should skip thr.kill on ALL non-green-thread platforms,
        #      possibly even those with green threads (because of risk of corruption)
        unless Kernel.const_defined?('JRuby')
          thr_list = @group.list.dup
          Thread.new do
            sleep 10
            thr_list.each do |thr|
              thr.kill if thr.alive?
            end
          end
        end

        @busy_count.set 0
        @started = false
      end
    end

    #
    # Determine whether all the threads in the pool are occupied with computations.
    # If this is true, there may be some delay in executing new jobs submitted via
    # enqueue.
    #
    # @return [Boolean] true if all the threads in the pool are busy
    #
    def busy?
      free_count == 0
    end

    #
    # Retrieve the number of currently managed threads
    #
    # @return [Integer] the number of currently managed threads
    def worker_count
      @count
    end

    #
    # Retrieve the number of currently executing threads
    #
    # @return [Integer] the number of busy threads
    #
    def busy_count
      @busy_count.value
    end

    #
    # how many tasks are waiting to execute
    #
    # @return [Integer] the number of tasks waiting
    #
    def backlog
      @queue.size
    end

    #
    # flush any queued but un-executed tasks
    #
    def flush
      @queue.clear
    end

    #
    # this is tricky as there may be one or more workers stuck in VERY long running jobs
    # so what we do is:
    #
    # Insert a job that stops processing
    # When it runs, we can be sure that all previous jobs have popped off the queue
    # However, previous jobs may still be running
    # So we have to ask each thread to pause until they've all paused
    #
    def join
      # wait until every thread has entered
      halt_n_times(@count).wait
    end

    def halt_n_times(n)
      halter = HaltObject.new(n)

      # ensure each thread gets a copy
      n.times { @queue << halter }
      halter
    end

    # @api private
    class HaltObject
      def initialize(count)
        @count = count
        @latch = CountDownLatch.new(count)
      end

      def halt!
        # notify that we're now waiting
        @latch.countdown!
        @latch.wait
      end

      def wait
        @latch.wait
      end
    end

    protected

    def _start_work
      @busy_count.update {|x| x + 1 }
    end

    def _end_work
      @busy_count.update {|x| x - 1 }
    end

  end

  #
  # Return the number of CPUs reported by the system
  #
  def self.cpu_count
    ZeevexConcurrency::Util::Platform.cpu_count
  end
end

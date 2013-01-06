require 'zeevex_concurrency'
require 'zeevex_concurrency/event_loop'
require 'countdownlatch'
require 'thread'
require 'atomic'

module ZeevexConcurrency::ThreadPool
  module Stubs
    def busy?
      free_count == 0
    end

    def worker_count
      -1
    end

    def busy_count
      -1
    end

    def free_count
      (worker_count - busy_count)
    end

    #
    # flush any queued but un-executed tasks
    #
    def flush
      true
    end

    #
    # Returns after all currently enqueued tasks complete - does not guarantee
    # that tasks are not enqueued while waiting
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
    # how many tasks are waiting
    #
    def backlog
      0
    end

    protected

    def _check_args(*args)
      args = args.reject {|f| f.nil? || !f.respond_to?(:call) }
      raise ArgumentError, "Must supply a callable or block" unless args.length == 1
      args[0]
    end
  end
  #
  # Use a single-threaded event loop to process jobs
  #
  class EventLoopAdapter
    include Stubs

    def initialize(loop = nil)
      @loop ||= ZeevexConcurrency::EventLoop.new
      start
    end

    def start
      @loop.start
    end

    def stop
      @loop.stop
    end

    def enqueue(callable = nil, &block)
      @loop.enqueue _check_args(callable, block)
    end

    def flush
      @loop.flush
      true
    end

    def backlog
      @loop.backlog
    end
  end

  #
  # Run job semi-synchronously (on a separate thread, but block on it)
  # We use a separate thread
  #
  class InlineThreadPool
    include Stubs

    def initialize(loop = nil)
      start
    end

    def start
      @started = true
    end

    def stop
      @started = false
    end

    def join
      true
    end

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
  class ThreadPerJobPool
    include Stubs

    def initialize
      @mutex = Mutex.new
      @group = ThreadGroup.new
      @busy_count = Atomic.new(0)

      start
    end

    def enqueue(runnable = nil, &block)
      raise "Must be started" unless @started
      callable = _check_args(runnable, block)
      thr = Thread.new do
        @busy_count.update {|x| x + 1}
        callable.call
        @busy_count.update {|x| x - 1}
      end
      @group.add(thr)
    end

    def start
      @started = true
    end

    def join
      @group.list.dup.each do |thr|
        thr.join
      end
      true
    end

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

    def busy_count
      @busy_count.value
    end

    def busy
      false
    end

    def worker_count
      @busy_count.value
    end
  end

  #
  # Use a fixed pool of N threads to process jobs
  #
  class FixedPool
    include Stubs

    def initialize(count = -1)
      if count == -1
        count = ZeevexConcurrency::ThreadPool.cpu_count * 2
      end
      @count = count
      @queue = Queue.new
      @mutex = Mutex.new
      @group = ThreadGroup.new
      @busy_count = Atomic.new(0)

      start
    end

    def enqueue(runnable = nil, &block)
      @queue << _check_args(runnable, block)
    end

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

    def stop
      @mutex.synchronize do
        return unless @started

        @stop_requested = true

        @group.list.each do |thr|
          thr.kill
        end

        @busy_count.set 0
        @started = false
      end
    end

    def busy?
      free_count == 0
    end

    def worker_count
      @count
    end

    def busy_count
      @busy_count.value
    end

    def free_count
      (worker_count - busy_count)
    end

    #
    # how many tasks are waiting
    #
    def backlog
      @queue.size
    end

    # flush queued jobs
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
      halter = HaltObject.new(@count)

      # ensure each thread gets a copy
      @count.times { @queue << halter }

      # wait until every thread has entered
      halter.wait
    end

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
    return Java::Java.lang.Runtime.getRuntime.availableProcessors if defined? Java::Java
    return File.read('/proc/cpuinfo').scan(/^processor\s*:/).size if File.exist? '/proc/cpuinfo'
    require 'win32ole'
    WIN32OLE.connect("winmgmts://").ExecQuery("select * from Win32_ComputerSystem").NumberOfProcessors
  rescue LoadError
    Integer `sysctl -n hw.ncpu 2>/dev/null` rescue 1
  end
end

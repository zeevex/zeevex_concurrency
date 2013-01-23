require File.join(File.dirname(__FILE__), '../spec_helper')
require 'zeevex_concurrency/executors/thread_pool.rb'
require 'zeevex_concurrency/executors/event_loop.rb'
require 'timeout'
require 'thread'
require 'atomic'
require 'countdownlatch'

describe ZeevexConcurrency::ThreadPool do
  let :mutex do
    Mutex.new
  end

  let :latch do
    CountDownLatch.new(1)
  end

  let :latch_wait_task do
    Proc.new { latch.wait }
  end

  let :queue do
    Queue.new
  end

  let :pop_task do
    Proc.new { queue.pop }
  end

  let :atom do
    Atomic.new(0)
  end

  around :each do |ex|
    Timeout::timeout(30) do
      ex.run
    end
  end

  before do
    queue
    pop_task
    atom
    latch_wait_task
    latch
  end

  def wait_until(timeout = 5, sleep_sec = 0.1)
    t_start = Time.now

    # go ahead and give up our timeslice as we might as well
    # let somebody else make the condition true
    Thread.pass unless yield
    until yield || (Time.now-t_start) >= timeout
      sleep sleep_sec
    end
    yield
  end

  shared_examples_for 'thread pool initialization' do
    context 'basic usage' do
      it 'should allow enqueue of a proc' do
        expect { pool.enqueue(Proc.new { true }) }.
            not_to raise_error
      end

      it 'should allow enqueue of a block' do
        expect {
          pool.enqueue do
            true
          end
        }.not_to raise_error
      end

      it 'should allow enqueue of a Promise, and return same promise' do
        promise = ZeevexConcurrency::Promise.new(Proc.new {true})
        expect { pool.enqueue(promise) }.not_to raise_error
      end

      it 'should NOT allow both a callable and a block' do
        expect {
          pool.enqueue(Proc.new{}) do
            true
          end
        }.to raise_error(ArgumentError)
      end
    end
  end

  shared_examples_for 'thread pool running tasks' do
    it 'should execute the task on a different thread' do
      pool.enqueue { queue << Thread.current.__id__ }
      queue.pop.should_not == Thread.current.__id__
    end

    it 'should allow enqueueing from an executed task, and execute both' do
      pool.enqueue do
        pool.enqueue { queue << "val2" }
        queue << "val1"
      end
      [queue.pop, queue.pop].sort.should == ["val1", "val2"]
    end

    it 'should execute a large number of tasks' do
      atom = Atomic.new(0)
      300.times do
        pool.enqueue do
          atom.update { |x| x+1 }
        end
      end
      Timeout::timeout(20) do
        while atom.value != 300
          sleep 0.5
        end
      end
      atom.value.should == 300
    end
  end

  shared_examples_for 'thread pool with parallel execution' do
    after do
      latch.countdown!
    end

    # must be an even number
    let :count do
      parallelism == -1 ? 32 : parallelism
    end

    it 'should increase busy_count when tasks start' do
      count.times { pool.enqueue { queue.pop } }
      wait_until { pool.busy_count == count }
      pool.busy_count.should == count
    end

    it 'should decrease busy_count when tasks finish' do
      count.times { pool.enqueue { queue.pop } }
      (count / 2).times { queue << "foo" }
      pool.enqueue { latch.countdown!; queue.pop }
      latch.wait
      # should we need the following?
      wait_until { pool.busy_count == (count / 2) + 1}
      pool.busy_count.should == (count / 2) + 1
    end

    #
    # TODO: this is pretty iffy - it doesn't really prove the assertion
    #
    it 'should return from join only when currently executing tasks finish' do
      (count / 2).times { pool.enqueue { sleep 1; atom.update {|x| x + 1} } }
      pool.join
      atom.value.should == count/2
    end
  end

  shared_examples_for 'thread pool with task queue' do
    it 'should give a total count of backlog in queue' do
      (parallelism + 1).times { pool.enqueue { queue.pop } }
      wait_until { pool.backlog == 1 }
      pool.backlog.should == 1
    end

    it 'should allow flushing jobs from the queue' do
      (parallelism + 1).times { pool.enqueue { queue.pop } }
      wait_until { pool.backlog == 1 }
      pool.flush
      pool.backlog.should == 0
    end

    it 'should not return from join if backlogged tasks have not run' do
      count = parallelism + 2
      count.times { pool.enqueue { sleep 10 } }
      expect {
        Timeout::timeout(2) { Thread.pass; pool.join }
      }.to raise_error(TimeoutError)
    end

    # TODO: this is another iffy one - how do we accurately meausure
    #       when join returns and how many tasks are waiting?
    it 'should return from join when backlogged tasks have' do
      count = parallelism * 2
      t_start = Time.now
      count.times { pool.enqueue { sleep 1; atom.update {|x| x + 1} } }
      pool.join
      t_end = Time.now
      atom.value.should == count
      # we expect roughly 2 seconds of wall clock time - each thread doing 2 tasks
      # which sleep for 1 second each
      (t_end - t_start).round.should == 2
    end
  end

  shared_examples_for 'thread pool control' do
    it 'should allow enqueueing after a stop/start' do
      # pending 'broken on jruby, and really in general'
      pool.stop
      pool.start
      pool.enqueue do
        queue << "ran"
      end
      Timeout::timeout(5) do
        queue.pop.should == "ran"
      end
    end
  end

  context 'FixedPool' do
    let :parallelism do
      32
    end
    let :pool do
      ZeevexConcurrency::ThreadPool::FixedPool.new(parallelism)
    end

    it_should_behave_like 'thread pool initialization'
    it_should_behave_like 'thread pool running tasks'
    it_should_behave_like 'thread pool control'
    it_should_behave_like 'thread pool with parallel execution'
    it_should_behave_like 'thread pool with task queue'

    it 'should indicate that the pool is busy when there are tasks in the queue' do
      (parallelism + 1).times { pool.enqueue { sleep 30 } }
      wait_until { pool.backlog == 1 }
      pool.should be_busy
    end

    it 'should indicate that there are no free workers when there are tasks in the queue' do
      (parallelism + 1).times { pool.enqueue { sleep 30 } }
      wait_until { pool.free_count == 0 }
      pool.free_count.should == 0
      pool.busy_count.should == parallelism
    end

  end

  context 'InlineThreadPool' do
    let :pool do
      ZeevexConcurrency::ThreadPool::InlineThreadPool.new
    end
    let :parallelism do
      1
    end

    it_should_behave_like 'thread pool initialization'
    it_should_behave_like 'thread pool running tasks'
    it_should_behave_like 'thread pool control'
  end

  context 'ThreadPerJobPool' do
    let :pool do
      ZeevexConcurrency::ThreadPool::ThreadPerJobPool.new
    end
    let :parallelism do
      -1
    end

    it_should_behave_like 'thread pool initialization'
    it_should_behave_like 'thread pool running tasks'
    it_should_behave_like 'thread pool control'
    it_should_behave_like 'thread pool with parallel execution'
  end

  context 'EventLoopAdapter' do
    let :loop do
      ZeevexConcurrency::EventLoop.new
    end
    let :pool do
      ZeevexConcurrency::ThreadPool::EventLoopAdapter.new loop
    end
    let :parallelism do
      1
    end

    it_should_behave_like 'thread pool initialization'
    it_should_behave_like 'thread pool running tasks'
    it_should_behave_like 'thread pool control'
    it_should_behave_like 'thread pool with task queue'
  end

end


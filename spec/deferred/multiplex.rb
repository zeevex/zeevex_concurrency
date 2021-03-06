require File.expand_path(File.join(File.dirname(__FILE__), '../spec_helper'))
require 'zeevex_concurrency/deferred/future.rb'
require 'zeevex_concurrency/deferred/multiplex.rb'
require 'set'
require 'countdownlatch'

#
# this test counts on a single-threaded worker pool
#
describe ZeevexConcurrency::Multiplex do

  let :queue do
    Queue.new
  end

  let :loop do
    loop = ZeevexConcurrency::ThreadPool::FixedPool.new(1)
  end

  let :latch do
    CountDownLatch.new(1)
  end

  before :each do
    pause_queue
    queue
    latch
    loop.start
    ZeevexConcurrency::Future.worker_pool = loop
  end

  around :each do |ex|
    Timeout::timeout(10) do
      ex.run
    end
  end

  let :pause_queue do
    Queue.new
  end

  def pause_futures
    pause_queue
    loop.enqueue do
      pause_queue.pop
    end
  end

  def resume_futures
    pause_queue << "continue"
  end

  # ensure previous futures have completed - serial single threaded worker pool necessary
  def wait_for_queue_to_empty
    ZeevexConcurrency::Future.create(Proc.new {}).wait
  end

  before do
    @futures = [*1..4].map do |x|
      ZeevexConcurrency::Future.create { queue.pop }
    end
    subject
  end
  clazz = ZeevexConcurrency::Multiplex

  context 'multiplex::first' do
    subject { clazz.new(@futures, 1) }

    it 'should not be ready if no futures are ready' do
      subject.ready?.should be_false
    end

    it 'should provide access to the set of unfinished futures before any have completed' do
      subject.dependencies.should == @futures
    end

    it 'should provide access to the set of unfinished futures before any have completed' do
      subject.waiting.should == @futures
    end

    it 'should be ready if one future is ready' do
      queue << 1
      subject.wait(1).should be_true
    end

    it 'should return the first future to complete in a list' do
      queue << 1
      subject.value.should == [@futures.first]
    end

    it 'should provide persistent access to the returned futures in #value' do
      queue << 1
      subject.value
      subject.value.should == [@futures.first]
    end

    it 'should provide access to the set of unfinished futures after one has completed' do
      queue << 1
      subject.value
      subject.waiting.should == @futures[1..-1]
    end

    class BlockyObserver
      def initialize(&block)
        @block = block
      end
      def update(*args)
        @block.call(*args)
      end
    end

    it 'should notify when one future completes' do
      pause_futures
      subject.add_observer(BlockyObserver.new { latch.countdown! } )
      queue << 1
      resume_futures
      subject.wait
      # we're assuming that all observers have been run by the time wait returns
      # otherwise we'd have to wait on the latch as well to be sure that our observer
      # ran
      latch.count.should == 0
    end

    it 'should notify when one future completes' do
      queue << 1
      subject.wait
      subject.add_observer(BlockyObserver.new { latch.countdown! } )
      latch.count.should == 0
    end
  end

  context 'multiplex::all' do
    clazz = ZeevexConcurrency::Multiplex

    subject { clazz.new(@futures, @futures.length) }

    it 'should not be ready if no futures are ready' do
      subject.ready?.should be_false
    end

    it 'should not be ready if two futures are ready' do
      2.times { queue << 1 }
      @futures[0].wait
      @futures[1].wait
      subject.ready?.should be_false
    end

    it 'should provide access to the set of dependent futures before any have completed' do
      subject.dependencies.should == @futures
    end

    it 'should provide access to the set of unfinished futures before any have completed' do
      subject.waiting.should == @futures
    end

    it 'should provide access to the set of unfinished futures after 2 have completed' do
      2.times { queue << 1 }
      @futures[0].wait
      @futures[1].wait
      @futures[2].wait(0.1)
      subject.waiting.size.should == 2
    end

    it 'should provide access to the set of completed futures after 2 have completed' do
      2.times { queue << 1 }
      @futures[0].wait
      @futures[1].wait
      @futures[2].wait(0.1)
      subject.complete.size.should == 2
    end

    it 'should be ready if all futures are ready' do
      4.times { queue << 1 }
      subject.wait(1).should be_true
    end

    it 'should return all completed futures in a list when done' do
      4.times { queue << 1 }
      Set.new(subject.value).should == Set.new(@futures)
    end

    it 'should provide persistent access to the returned futures in #value' do
      4.times { queue << 1 }
      Set.new(subject.value).should == Set.new(@futures)
      Set.new(subject.value).should == Set.new(@futures)
    end

    it 'should provide access to the set of unfinished futures after one has completed' do
      3.times { queue << 1 }
      subject.wait(0.5).should == false
    end

    it 'should not notify when first future completes' do
      pause_futures
      subject.add_observer(BlockyObserver.new { latch.countdown! } )
      queue << 1
      resume_futures
      sleep 0.3
      latch.count.should == 1
    end

    it 'should notify only when all futures complete' do
      pause_futures
      subject.add_observer(BlockyObserver.new { latch.countdown! } )
      4.times { queue << 1 }
      resume_futures
      subject.wait
      latch.count.should == 0
    end
  end

  context 'filtering' do
    clazz = ZeevexConcurrency::Multiplex

    subject do
    end
    let :mux do
      clazz.new(@futures, 1, :filter => @filter)
    end

    it 'should not be ready if no futures have yet passed the filter' do
      @filter = lambda {|x| false}
      2.times { queue << 1 }
      @futures[0].wait
      @futures[1].wait
      mux.ready?.should be_false
    end

    it 'should signal error if not enough futures passed the filter' do
      @filter = lambda {|x| false}
      @futures.count.times { queue << 1 }
      @futures.last.wait
      expect { mux.value }.to raise_error
    end

    it 'should return an empty list to value(false) if no futures passed the filter' do
      @filter = lambda {|x| false}
      @futures.count.times { queue << 1 }
      @futures.last.wait
      mux.value(false).should == []
    end

    it 'should return the first future to pass the filter' do
      @filter = lambda {|x| x.value == 3 }
      @futures.count.times { |i| queue << i }
      mux.value.first.value.should == 3
    end
  end

  context '.either' do
    let :equeue do
      Queue.new
    end
    let :future1 do
      ZeevexConcurrency.future { equeue.pop }
    end
    let :future2 do
      ZeevexConcurrency.future { equeue.pop }
    end

    let :either do
      clazz.either(future1, future2)
    end
    subject do
    end

    it 'should be a future' do
      either.should be_a(ZeevexConcurrency::Future)
    end

    it 'should not be ready at first' do
      either.should_not be_ready
    end

    it 'should return the future that completes first' do
      ZeevexConcurrency::Future.worker_pool = ZeevexConcurrency::ThreadPool::FixedPool.new(1)
      equeue << "winrar"
      equeue << "loser"
      either.value.should == "winrar"
    end
  end

  context '.first_of' do
    let :firstof do
      clazz.first_of(*@futures)
    end
    subject do
    end

    it 'should return the future that completes first' do
      ZeevexConcurrency::Future.worker_pool = ZeevexConcurrency::ThreadPool::FixedPool.new(1)
      queue << "winrar"
      3.times { queue << "loser" }
      @futures.each {|f| f.wait}
      firstof.value.should == "winrar"
    end

  end

end


require File.join(File.dirname(__FILE__), '../spec_helper')
require 'zeevex_concurrency/deferred/future.rb'
require 'zeevex_concurrency/executors/event_loop.rb'
require 'zeevex_concurrency/executors/thread_pool.rb'

#
# this test counts on a single-threaded worker pool
#
describe ZeevexConcurrency::Future do
  clazz = ZeevexConcurrency::Future

  let :empty_proc do
    Proc.new { 8800 }
  end

  let :sleep_proc do
    Proc.new { sleep 60 }
  end

  let :queue do
    Queue.new
  end

  let :loop do
    loop = ZeevexConcurrency::ThreadPool::FixedPool.new(1)
  end

  before :each do
    queue
    pause_queue
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

  context 'argument checking' do
    it 'should require a callable or a block' do
      expect { clazz.create }.
        to raise_error(ArgumentError)
    end

    it 'should not allow both a callable AND a block' do
      expect {
        clazz.create(empty_proc) do
          1
        end
      }.to raise_error(ArgumentError)
    end

    it 'should accept a proc' do
      expect { clazz.create(empty_proc) }.
        not_to raise_error(ArgumentError)
    end

    it 'should accept a block' do
      expect {
        clazz.create do
          1
        end
      }.not_to raise_error(ArgumentError)
    end
  end

  context 'before receiving value' do
    subject { clazz.create(sleep_proc) }
    it { should_not be_ready }
  end

  context 'after executing' do
    subject {
      clazz.create do
        @counter += 1
      end
    }

    before do
      @counter = 55
      subject.wait
    end

    it          { should be_ready }
    its(:value) { should == 56 }
    it 'should return same value for repeated calls' do
      subject.value
      subject.value.should == 56
    end
  end

  context 'with exception' do
    class FooBar < StandardError; end
    subject do
      clazz.create do
        # binding.pry
        raise FooBar, "test"
      end
    end

    before do
      subject.wait
    end

    it 'should be ready' do
      subject.should be_ready
    end
    
    it 'should reraise exception' do
      expect { subject.value }.
        to raise_error(FooBar)
    end

    it 'should optionally not reraise' do
      expect { subject.value(false) }.
        not_to raise_error(FooBar)
      subject.value(false).should be_a(FooBar)
    end
  end

  context '#wait' do
    subject { clazz.create(Proc.new { queue.pop }) }
    it 'should wait for 2 seconds' do
      t_start = Time.now
      res = subject.wait 2
      t_end = Time.now
      (t_end-t_start).round.should == 2
      res.should be_false
    end

    it 'should return immediately if ready' do
      t_start = Time.now
      queue << 99
      res = subject.wait 2
      t_end = Time.now
      (t_end-t_start).round.should == 0
      res.should be_true
    end
  end

  context 'observing' do
    let :observer do
      mock()
    end

    context 'registered before the future runs' do
      subject { clazz.create(Proc.new { @callable.call }, :observer => observer) }
      it 'should notify observer after set_result' do
        pause_futures
        @callable = Proc.new { 10 }
        observer.should_receive(:update).with(subject, 10, true)
        resume_futures
        wait_for_queue_to_empty
      end

      it 'should notify observer after set_result raises exception' do
        pause_futures
        @callable = Proc.new { raise "foo" }
        observer.should_receive(:update).with(subject, kind_of(Exception), false)
        resume_futures
        wait_for_queue_to_empty
      end
    end

    context 'after execution has completed' do
      subject { clazz.create(Proc.new { @callable.call }) }
      it 'should notify newly registered observer with value' do
        @callable = Proc.new { 10 }
        # cause future to be created and run
        subject
        observer.should_receive(:update).with(subject, 10, true)
        subject.wait
        subject.add_observer(observer)
        wait_for_queue_to_empty
      end

      it 'should notify newly registered observer with exception' do
        @callable = Proc.new { raise "foo" }
        # cause future to be created and run
        subject
        observer.should_receive(:update).with(subject, kind_of(Exception), false)
        subject.wait
        subject.add_observer(observer)
        wait_for_queue_to_empty
      end
    end
  end

  context 'cancelling' do
    subject do
      clazz.create(Proc.new { @value += 1})
    end

    before do
      @value = 100
      pause_futures
      subject
    end

    it 'should not be cancelled at creation time' do
      subject.should_not be_cancelled
    end

    it 'should not be cancelled after execution' do
      resume_futures
      subject.wait
      subject.should_not be_cancelled
    end

    it 'should not be cancelled after raising an exception' do
      future = clazz.create(Proc.new { raise "bar" })
      resume_futures
      future.wait
      future.should_not be_cancelled
    end

    it 'should be cancelled after cancellation but before execution' do
      subject.cancel
      subject.should be_cancelled
    end

    it 'should not be marked as executed after cancellation but before execution' do
      subject.cancel
      subject.should_not be_executed
    end

    it 'should be marked as ready after cancellation but before execution' do
      subject.cancel
      subject.should be_ready
    end

    it 'should be cancelled after cancellation and attempted execution' do
      subject.cancel
      resume_futures
      wait_for_queue_to_empty
      subject.should be_cancelled
    end

    it 'should skip execution after cancellation' do
      subject.cancel
      resume_futures
      wait_for_queue_to_empty
      subject.should be_cancelled
      subject.should_not be_executed
      @value.should == 100
    end

    it 'should not allow cancellation after execution' do
      resume_futures
      wait_for_queue_to_empty
      subject.cancel.should be_false
    end

    it 'should raise exception if #value is called on cancelled future' do
      subject.cancel
      resume_futures
      wait_for_queue_to_empty
      expect { subject.value }.
        to raise_error(ZeevexConcurrency::Delayed::CancelledException)
    end

    it 'should return from wait after processing when cancelled' do
      subject.cancel
      resume_futures
      wait_for_queue_to_empty
      Timeout::timeout(1) { subject.wait }
    end

    it 'should return from wait before processing when cancelled' do
      subject.cancel
      Timeout::timeout(1) { subject.wait }
    end
  end

  context 'access from multiple threads' do
    let :future do
      clazz.create(Proc.new { @value += 1})
    end

    before do
      @value = 20
      pause_futures
      future
      queue
      threads = []
      5.times do
        threads << Thread.new do
          queue << future.value
        end
      end
      Thread.pass
      @queue_size_before_set = queue.size
      resume_futures
      threads.map &:join
    end

    it 'should block all threads before set_result' do
      @queue_size_before_set.should == 0
    end

    it 'should allow all threads to receive a value' do
      queue.size.should == 5
    end

    it 'should only evaluate the computation once' do
      @value.should == 21
    end

    it 'should send the same value to all threads' do
      list = []
      5.times { list << queue.pop }
      list.should == [21,21,21,21,21]
    end
  end
end


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
    it          { should_not be_failed }
    it          { should be_successful }

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

    it { should be_ready }
    it { should be_failed }
    it { should_not be_successful }

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
      subject.should be_failed
      subject.should_not be_successful
    end

    it 'should be cancelled after cancellation and attempted execution' do
      subject.cancel
      resume_futures
      wait_for_queue_to_empty
      subject.should be_cancelled
      subject.should be_failed
      subject.should_not be_successful
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



  context 'callbacks' do
    let :observer do
      mock('observer')
    end
    subject do
      clazz.create(Proc.new {@callable.call})
    end

    before do
      pause_futures
    end

    def finish_test
      subject
      resume_futures
      wait_for_queue_to_empty
    end

    context 'registered before the future runs' do
      it 'should notify onSuccess observer' do
        @callable = Proc.new { 10 }
        subject.onSuccess { |val| observer.succeed(val) }
        observer.should_receive(:succeed).with(10)
        finish_test
      end

      it 'should notify onFailure observer after set_result raises exception' do
        @callable = Proc.new { raise "foo" }
        subject.onFailure { |val| observer.fail(val) }
        observer.should_receive(:fail).with(kind_of(Exception))
        finish_test
      end

      it 'should notify onCompletion observer on success' do
        @callable = Proc.new { 10 }
        subject.onComplete { |val, successFlag| observer.complete(val, successFlag) }
        observer.should_receive(:complete).with(10, true)
        finish_test
      end

      it 'should notify onCompletion observer after set_result raises exception' do
        @callable = Proc.new { raise "foo" }
        subject.onComplete { |val, successFlag| observer.complete(val, successFlag) }
        observer.should_receive(:complete).with(kind_of(Exception), false)
        finish_test
      end
    end

    #context 'after execution has completed' do
    #  subject { clazz.create(Proc.new { @callable.call }) }
    #  it 'should notify newly registered observer with value' do
    #    @callable = Proc.new { 10 }
    #    # cause future to be created and run
    #    subject
    #    observer.should_receive(:update).with(subject, 10, true)
    #    subject.wait
    #    subject.add_observer(observer)
    #    wait_for_queue_to_empty
    #  end
    #
    #  it 'should notify newly registered observer with exception' do
    #    @callable = Proc.new { raise "foo" }
    #    # cause future to be created and run
    #    subject
    #    observer.should_receive(:update).with(subject, kind_of(Exception), false)
    #    subject.wait
    #    subject.add_observer(observer)
    #    wait_for_queue_to_empty
    #  end
    #end
  end

  context 'map module' do
    let :observer do
      mock('observer')
    end
    let :base do
      clazz.create(Proc.new {@callable.call})
    end


    before do
      pause_futures
      @callable = lambda { 10 }
      @map_callable = lambda {|x| x * 2 }
    end

    def finish_test
      subject
      resume_futures
      wait_for_queue_to_empty
    end

    context '#map' do
      subject do
        base.map do |val|
          @map_callable.call(val)
        end
      end
      it 'should be a future' do
        subject.should be_a(clazz)
      end

      it 'should be a new future' do
        subject.__id__.should_not == base.__id__
      end

      it 'should not be ready until base future is ready' do
        subject.should_not be_ready
      end

      it 'should return the proper value' do
        resume_futures
        subject.value.should == 20
      end

      it 'should call onsuccess' do
        ons = mock('onsuccess')
        ons.should_receive(:done).with(20)
        subject.onSuccess {|val| ons.done(val) }
        resume_futures
        subject.wait
        finish_test
      end

      context 'failure' do
        before do
          @callable     = lambda { raise "foo" }
          @map_callable = lambda { observer.skip }
        end

        it 'should fail without executing block if base future fails' do
          observer.should_not_receive(:skip)
          finish_test
        end

        it 'should return an exception' do
          resume_futures
          subject.value(false).should be_a(Exception)
        end

        it 'should return the same exception that was raised in base' do
          resume_futures
          base.value(false).should == subject.value(false)
        end

      end
    end

    context '#fallbackTo' do
      subject do
        base.fallback_to do
          @fallback_callable.call
        end
      end

      it { should be_a(ZeevexConcurrency::Future) }

      context 'when original future succeeds' do
        it 'should return value of original future on success' do
          @callable = lambda { 77 }
          resume_futures
          subject.value.should == 77
        end

        it 'should not execute fallbackTo block on success' do
          @callable = lambda { 77 }
          @fallback_callable = lambda { observer.fail }
          observer.should_not_receive :fail
          resume_futures
          subject
        end
      end

      context 'when original future fails' do
        before do
          @callable = lambda { raise "foo" }
          @fallback_callable = lambda { observer.fellback }
        end
        it 'should execute fallbackTo block on base failure' do
          observer.should_receive(:fellback).and_return(65)
          resume_futures
          subject.value.should == 65
          base.value(false).should be_a(Exception)
        end
        it 'should return exception of fallbackTo block on cascading failure' do
          @fallback_callable = lambda { raise ArgumentError, "inner" }
          resume_futures
          expect { subject.value }.to raise_error
          subject.value(false).should be_a(ArgumentError)
        end
      end

    end

    context '#transform' do
      subject do
        base.transform @result_callable, @failure_callable
      end

      it { should be_a(ZeevexConcurrency::Future) }

      before do
        @result_callable  = lambda {|x| x + 50 }
        @failure_callable = lambda {|x| IOError.new "test" }
      end

      context 'when original future succeeds' do
        it 'should return value of original future on success' do
          @callable        = lambda { 77 }
          @result_callable = lambda {|x| x + 50 }
          resume_futures
          subject.value.should == 127
        end
      end

      context 'when original future fails' do
        before do
          @callable = lambda { raise "foo" }
        end
        it 'should return transformed IOError' do
          resume_futures
          expect { subject.value }.to raise_error(IOError)
        end
        it 'should return an exception thrown by error transformer' do
          @failure_callable = lambda {|x| raise NameError }
          resume_futures
          expect { subject.value }.to raise_error(NameError)
        end
        it 'should return value if error transformer returns a non-exception' do
          @failure_callable = lambda {|x| 9000 }
          resume_futures
          subject.value.should == 9000
        end
      end

    end

    context '#filter' do
      subject do
        base.filter &@filter_proc
      end

      it { should be_a(ZeevexConcurrency::Future) }

      before do
        @filter_proc = lambda { |x| true }
      end

      context 'when original future succeeds' do
        it 'should return result of original future when it matches filter' do
          @filter_proc = lambda {|x| x % 2 == 0 }
          @callable    = lambda { 100 }
          resume_futures
          subject.value.should == 100
        end
        it 'should signal failure when result does not match filter' do
          @filter_proc = lambda {|x| x % 2 == 1 }
          @callable    = lambda { 100 }
          resume_futures
          expect { subject.value}.to raise_error(IndexError)
        end
      end

      context 'when original future fails' do
        before do
          @callable = lambda { raise IOError, "foo" }
        end
        it 'should return the exception from the original future' do
          resume_futures
          expect { subject.value }.to raise_error(IOError)
        end
      end
    end

    context '#and_then' do
      subject do
        base.and_then do |result, success|
          observer.record(result, success, 1) if @record
          @accumulator += (success ? result * 2 : 12)
        end.and_then do |result, success|
          observer.record(result, success, 2) if @record
          @accumulator *= 2
        end
      end
      before do
        @accumulator = 0
        @callable    = lambda { 1000 }
      end
      it 'should be a future' do
        subject.should be_a(clazz)
      end
      it 'should not be ready until base future is ready' do
        subject.should_not be_ready
      end
      it 'should return the value returned from the original future' do
        resume_futures
        subject.value.should == 1000
      end
      it 'should have executed all the chained futures for side effects' do
        resume_futures
        subject.wait
        @accumulator.should == 4000
      end
      it 'should have run and_then blocks in order' do
        @record = true
        observer.should_receive(:record).with(1000, true, 1)
        observer.should_receive(:record).with(1000, true, 2)
        resume_futures
        subject.wait
      end

      context 'failure in base future' do
        before do
          @callable     = lambda { raise ArgumentError, "foo" }
        end
        it 'should return original value of original future' do
          resume_futures
          subject.value(false).should be_a(ArgumentError)
        end
        it 'should return the same exception that was raised in base' do
          resume_futures
          base.value(false).should == subject.value(false)
        end
        it 'should have run and_then blocks in order' do
          @record = true
          observer.should_receive(:record).with(kind_of(Exception), false, 1)
          observer.should_receive(:record).with(kind_of(Exception), false, 2)
          resume_futures
          subject.wait
          @accumulator.should == 24
        end
      end

      context 'failure in and_then block' do
        subject do
          base.and_then do |result, success|
            raise IndexError, "first andthen"
          end.and_then do |result, success|
            observer.record(result, success, 987) if @record
            @accumulator = 7500
          end
        end

        it 'should still return value of original future' do
          resume_futures
          subject.value.should == 1000
        end
        it 'should execute second block even if first fails' do
          @record = true
          observer.should_receive(:record).with(1000, true, 987)
          resume_futures
          subject.wait
          @accumulator.should == 7500
        end
      end
    end

    context '#flat_map' do
      # we'll have one future waiting on another, so we need some actual concurrency
      # in these tests
      let :loop do
        loop = ZeevexConcurrency::ThreadPool::FixedPool.new(4)
      end

      subject do
        base.flat_map do |val|
          @map_callable.call(val)
        end
      end
      before do
        @callable     = lambda { 200 }
        @map_callable = lambda { |x| ZeevexConcurrency.future { x + 40 } }
      end
      it 'should be a future' do
        subject.should be_a(clazz)
      end
      it 'should not be ready until base future is ready' do
        subject.should_not be_ready
      end
      it 'should return the proper value, not a future' do
        resume_futures
        subject.value.should == 240
      end

      context 'failure in base future' do
        before do
          @callable     = lambda { raise ArgumentError, "foo" }
        end
        it 'should return an exception' do
          resume_futures
          subject.value(false).should be_a(ArgumentError)
        end
        it 'should return the same exception that was raised in base' do
          resume_futures
          base.value(false).should == subject.value(false)
        end
      end

      context 'failure in outer mapped future' do
        before do
          @map_callable = lambda { |x| raise ArgumentError, "foo" }
        end
        it 'should return an exception' do
          resume_futures
          subject.value(false).should be_a(ArgumentError)
        end
      end

      context 'failure in inner mapped future' do
        before do
          @map_callable = lambda { |x| ZeevexConcurrency.future { raise ArgumentError, "foo" } }
        end
        it 'should return an exception' do
          resume_futures
          subject.value(false).should be_a(ArgumentError)
        end
      end
    end

    context '#for_each' do
      before do
        @res = 0
      end
      it 'should invoke the block on the value of a successful future' do
        fut = clazz.create { 1975 }
        resume_futures
        fut.foreach { |x| @res = x }
        @res.should == 1975
      end

      it 'should do nothing if the future has failed' do
        fut = clazz.create { raise "NO" }
        resume_futures
        fut.foreach { |x| @res = x }
        @res.should == 0
      end
    end

  end
end


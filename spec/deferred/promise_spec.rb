require File.expand_path(File.join(File.dirname(__FILE__), '../spec_helper'))
require 'zeevex_concurrency/deferred/future.rb'
require 'zeevex_concurrency/executors/event_loop.rb'

describe ZeevexConcurrency::Promise do
  clazz = ZeevexConcurrency::Promise

  around :each do |ex|
    Timeout::timeout(10) do
      ex.run
    end
  end

  context 'argument checking' do

    it 'should allow neither a callable nor a block' do
      expect { clazz.new }.
        not_to raise_error(ArgumentError)
    end

    it 'should not allow both a callable AND a block' do
      expect {
        clazz.new(Proc.new { 2 }) do
          1
        end
      }.to raise_error(ArgumentError)
    end

    it 'should accept a proc' do
      expect { clazz.new(Proc.new {}) }.
        not_to raise_error(ArgumentError)
    end

    it 'should accept a block' do
      expect {
        clazz.new do
          1
        end
      }.not_to raise_error(ArgumentError)
    end
  end

  context 'before receiving value' do
    subject { clazz.new() }
    it { should_not be_ready }
  end

  context 'after using set_result' do
    subject { clazz.new(nil) }
    before do
      @counter = 55
      subject.set_result { @counter += 1 }
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
      clazz.new lambda {
        raise FooBar, "test"
      }
    end

    before do
      subject.execute
    end

    it { should be_ready }
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
    subject { clazz.new }
    it 'should wait for 2 seconds' do
      t_start = Time.now
      res = subject.wait 2
      t_end = Time.now
      (t_end-t_start).round.should == 2
      res.should be_false
    end

    it 'should return immediately if ready' do
      t_start = Time.now
      subject.set_result { 99 }
      res = subject.wait 2
      t_end = Time.now
      (t_end-t_start).round.should == 0
      res.should be_true
    end
  end

  context 'observing' do
    subject { clazz.new(nil) }
    let :observer do
      mock()
    end

    it 'should notify observer after set_result' do
      observer.should_receive(:update).with(subject, 10, true)
      subject.add_observer observer
      subject.set_result { 10 }
    end

    it 'should notify observer after set_result raises exception' do
      observer.should_receive(:update).with(subject, kind_of(Exception), false)
      subject.add_observer observer
      subject.set_result { raise "foo" }
    end

    it 'should notify observer after #execute' do
      future = clazz.new(Proc.new { 4 + 20 })
      observer.should_receive(:update)
      future.add_observer observer
      future.execute
    end

    context 'after execution has completed' do
      it 'should notify observer after set_result' do
        observer.should_receive(:update).with(subject, 10, true)
        subject.set_result { 10 }
        subject.add_observer observer
      end

      it 'should notify observer after set_result raises exception' do
        observer.should_receive(:update).with(subject, kind_of(Exception), false)
        subject.set_result { raise "foo" }
        subject.add_observer observer
      end

      it 'should notify observer after #execute' do
        future = clazz.new(Proc.new { 4 + 20 })
        observer.should_receive(:update)
        future.execute
        future.add_observer observer
      end
    end
  end

  context 'access from multiple threads' do
    subject { clazz.new(nil) }

    before do
      @value = 20
      subject
      @queue = Queue.new
      threads = []
      5.times do
        threads << Thread.new do
          @queue << subject.value
        end
      end
      Thread.pass
      @queue_size_before_set = @queue.size
      subject.set_result { @value += 1 }
      threads.map &:join
    end

    it 'should block all threads before set_result' do
      @queue_size_before_set.should == 0
    end

    it 'should allow all threads to receive a value' do
      @queue.size.should == 5
    end

    it 'should only evaluate the computation once' do
      @value.should == 21
    end

    it 'should send the same value to all threads' do
      list = []
      5.times { list << @queue.pop }
      list.should == [21,21,21,21,21]
    end
  end
end


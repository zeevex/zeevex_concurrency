require File.join(File.dirname(__FILE__), 'spec_helper')
require 'zeevex_concurrency/delay.rb'

describe ZeevexConcurrency::Delay do
  clazz = ZeevexConcurrency::Delay

  before do
    @counter = 200
  end
  let :proccy do
    Proc.new { @counter += 1}
  end

  around :each do |ex|
    Timeout::timeout(30) do
      ex.run
    end
  end

  context 'argument checking' do
    it 'should not allow neither a callable nor a block' do
      expect { clazz.new }.
        to raise_error(ArgumentError)
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

  context 'at creation time' do
    subject { clazz.new(proccy) }
    it { should be_ready }
  end

  context 'after first deference' do
    subject { clazz.new(proccy) }
    before do
      subject.value
    end

    it          { should be_ready }
    its(:value) { should == 201 }
    it 'should return same value for repeated calls' do
      subject.value
      subject.value.should == 201
    end
  end

  context 'with exception' do
    class FooBar < StandardError; end
    subject do
      clazz.new lambda {
        raise FooBar, "test"
      }
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
    subject { clazz.new(proccy) }

    it 'should return immediately' do
      t_start = Time.now
      res = subject.wait 2
      t_end = Time.now
      (t_end-t_start).round.should == 0
      res.should be_true
    end
  end

  context 'observing' do
    subject { clazz.new(proccy) }
    let :observer do
      mock()
    end

    it 'should notify observer after value deref' do
      observer.should_receive(:update).with(subject, 201, true)
      subject.add_observer observer
      subject.value
    end

    it 'should notify observer after value deref raises exception' do
      edelay = clazz.new(Proc.new { raise "foo" })
      observer.should_receive(:update).with(edelay, kind_of(Exception), false)
      edelay.add_observer observer
      edelay.value rescue nil
    end
  end

  context 'access from multiple threads' do

    let :pause_queue do
      Queue.new
    end

    subject {
      clazz.new do
        pause_queue.pop
        @counter += 1
      end
    }
    let :queue do
      Queue.new
    end

    before do
      subject
      queue
      pause_queue

      threads = []
      5.times do
        threads << Thread.new do
          queue << subject.value
        end
      end
      Thread.pass
      @queue_size_before_set = queue.size
      pause_queue << "foo"
      threads.map &:join
    end

    it 'should block all threads before value derefed' do
      @queue_size_before_set.should == 0
    end

    it 'should allow all threads to receive a value' do
      queue.size.should == 5
    end

    it 'should only evaluate the computation once' do
      @counter.should == 201
    end

    it 'should send the same value to all threads' do
      list = []
      5.times { list << queue.pop }
      list.should == [201,201,201,201,201]
    end
  end
end


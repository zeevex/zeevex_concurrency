require File.join(File.dirname(__FILE__), '../spec_helper')
require 'zeevex_concurrency/scope/var.rb'
require 'thread'

describe ZeevexConcurrency::Var do
  clazz = ZeevexConcurrency::Var
  Var = ZeevexConcurrency::Var

  let :delegate do
    mock()
  end

  let :queue do
    Queue.new
  end

  context '#new' do
    it 'should accept a nil binding' do
      Var.new
    end
    it 'should accept a root binding value' do
      Var.new(delegate)
    end
    it 'should accept a default binding block' do
      Var.new do
        22
      end
    end
  end

  context 'Var.get' do
    it 'should retrieve value from bound var' do
      Var.get(Var.new(22)).should == 22
    end
    it 'should raise exception from bound var' do
      expect { Var.get(Var.new) }.to raise_error(ZeevexConcurrency::UnboundError)
    end
    it 'should return default value from unbound var if supplied' do
      Var.get(Var.new, "foo").should == "foo"
    end
  end

  context 'unbound variable' do
    subject do
      Var.new
    end
    it 'should not be bound' do
      Var.bound?(subject).should_not be_true
    end
    it 'should throw an exception if dereferenced' do
      expect { subject.foo }.to raise_error(ZeevexConcurrency::UnboundError)
    end
    it 'should allow setting via Var.set_root' do
      expect { Var.set_root(subject, 132321) }.not_to raise_error
      subject.should == 132321
    end
    it 'should accept a value in a binding form' do
      Var.with_bindings([[subject, 99999]]) do
        subject.should == 99999
      end
    end
  end

  context 'root-bound variable' do
    subject do
      Var.new(delegate)
    end
    it 'should be bound' do
      Var.bound?(subject).should be_true
    end
    it_should_behave_like 'a transparent proxy'
    it 'should appear as default value in all threads' do
      Thread.new { Var.get(subject) }.value.should == Thread.new { Var.get(subject) }.value
    end
    it 'should allow overriding in a thread via Var.set' do
      Thread.new do
        Var.set(subject, 12340)
        Var.get(subject)
      end.value.should == 12340
      Var.get(subject).should_not == 12340
    end
  end

  context 'when bound with proc' do
    subject do
      Var.new { @counter += 1; Thread.current.__id__ }
    end
    before do
      subject
      @counter = 0
    end
    it 'should be bound' do
      Var.bound?(subject).should be_true
    end
    it 'should not initially be thread-bound' do
      Var.thread_bound?(subject).should be_false
    end
    it 'should return the appropriate value' do
      subject.should == Thread.current.__id__
    end
    it 'should calculate a new default value in each thread' do
      subject.should_not == Thread.new { Var.get(subject) }.value
    end
    it 'should allow overriding in a thread via Var.set' do
      Thread.new do
        Var.set(subject, "newval")
        Var.get(subject)
      end.value.should == "newval"
    end
    it 'should not call proc more than once per thread' do
      Var.get(subject)
      Var.get(subject)
      @counter.should == 1
    end
  end

  context 'thread-local value' do
    it 'should not be affected when root binding is altered' do
      Var.set(subject, 1000)
      Var.set_root(subject, "foo")
      subject.should == 1000
    end
    it 'should allow setting via Var.set' do
      Var.with_bindings([[subject, 9991]]) do
        Var.set(subject, "bcbcv")
        subject.should == "bcbcv"
      end
    end
    it 'should not affect values in other threads when set' do
      t1 = Thread.new do
        Var.set(subject, "t1")
        queue.pop
        Var.get(subject)
      end
      Var.set(subject, "mainthreadval")
      queue << "continue"
      t1.value.should == "t1"
    end
    it 'should allow a binding scope' do
      Var.set(subject, "Abcd")
      Var.with_bindings([[subject, 9991]]) do
        subject.should == 9991
      end
      subject.should == "Abcd"
    end
  end

  context 'dynamic scope blocks' do
    subject do
      Var.new("rootval")
    end
    it 'should override root binding' do
      Var.with_bindings([[subject, "scopeval"]]) do
        subject.should == "scopeval"
      end
    end
    it 'should override thread-local binding' do
      Var.set(subject, "threadval")
      Var.with_bindings([[subject, "scopeval"]]) do
        subject.should == "scopeval"
      end
    end
    it 'should not affect other threads' do
      t1 = Thread.new do
        Var.set(subject, "t1")
        queue.pop
        Var.get(subject)
      end
      Var.with_bindings([[subject, "scopeval"]]) do
        queue << "continue"
        t1.value.should == "t1"
      end
    end
    it 'should unwind after block terminates' do
      Var.with_bindings([[subject, "scopeval"]]) do
      end
      subject.should == "rootval"
    end
    it 'should unwind even with exception' do
      begin
        Var.with_bindings([[subject, "scopeval"]]) do
          raise "foo"
        end
      rescue
      end
      subject.should == "rootval"
    end
    it 'should unwind properly with Var.set in middle' do
      v2 = Var.new("v2")
      Var.with_bindings [[subject, "scopeval"]] do
        Var.set(v2, "innerv2")
      end
      subject.should == "rootval"
    end
  end


end


require File.join(File.dirname(__FILE__), '../spec_helper')
require 'zeevex_concurrency/scope/thread_bound_object.rb'
require 'thread'

describe ZeevexConcurrency::ThreadBoundObject do
  clazz = ZeevexConcurrency::ThreadBoundObject

  let :obj do
    mock()
  end

  let :thread do
    Thread.new do
      sleep
    end
  end

  before do
    obj
    thread
  end

  after do
    thread.kill
  end

  def bound_to_me(obj)
    obj.instance_variable_get("@bound_thread_id").should == Thread.current.__id__
  end

  context 'constructor argument checking' do
    it 'should require an object' do
      expect { clazz.new }.
        to raise_error(ArgumentError)
    end

    it 'should accept a thread to pre-bind to' do
      expect {
        clazz.new(obj, thread)
      }.not_to raise_error
    end

    it 'should not accept a non-thread object to pre-bind to' do
      expect { clazz.new(obj, "foo") }.
        to raise_error(ArgumentError)
    end

    it 'should interpret a nil thread argument to mean "prebind to this thread"' do
      obj = clazz.new(obj, nil)
      obj.__bound?.should be_true
      bound_to_me(obj).should be_true
    end
  end

  context '#__bind' do
    subject do
      clazz.new(obj)
    end
    it 'should accept a thread argument' do
      clazz.bind(subject, Thread.current)
      subject.__bound?.should be_true
      bound_to_me(subject).should be_true
    end
    it 'should interpret no arg to mean "this thread"' do
      clazz.bind(subject)
      subject.__bound?.should be_true
      bound_to_me(subject).should be_true
    end
  end

  context 'when explicitly bound to this thread' do
    subject do
      clazz.new(obj, Thread.current)
    end
    it 'should be bound' do
      subject.__bound?.should be_true
    end
    it 'should allow messages' do
      obj.should_receive(:foo)
      subject.foo
    end
    it 'should allow unbinding' do
      subject.__unbind
      subject.__bound?.should be_false
    end
    it 'should allow unbinding' do
      subject.__nullbind
      subject.__bound?.should be_false
    end
  end

  context 'when explicitly bound to other thread' do
    subject do
      clazz.new(obj, thread)
    end
    it 'should be bound' do
      subject.__bound?.should be_true
    end
    it 'should not allow messages' do
      expect { subject.foo }.
        to raise_error(ZeevexConcurrency::BindingError)
    end
    it 'should not allow unbinding' do
      expect { subject.__unbind }.
        to raise_error(ZeevexConcurrency::BindingError)
    end
    it 'should not allow nullbinding' do
      expect { subject.__nullbind }.
        to raise_error(ZeevexConcurrency::BindingError)
    end
    it 'should not allow binding to another thread' do
      expect { subject.__bind_to_thread(Thread.current) }.
        to raise_error(ZeevexConcurrency::BindingError)
    end
  end

  context 'when unbound' do
    subject do
      clazz.new(obj)
    end
    it 'should not be bound' do
      subject.__bound?.should be_false
    end
    it 'should allow messages' do
      obj.should_receive(:foo)
      subject.foo
    end
    it 'should auto-bind on first message receipt' do
      obj.should_receive(:foo)
      subject.foo
      subject.__bound?.should be_true
    end
    it 'should not allow messages from another thread after first message receipt' do
      obj.should_receive(:foo)
      Thread.new { subject.foo }.join
      expect { subject.foo }.to raise_error(ZeevexConcurrency::BindingError)
    end
    it 'should allow unbinding' do
      expect { subject.__unbind }.
        not_to raise_error
    end
    it 'should allow nullbinding' do
      expect { subject.__nullbind }.
        not_to raise_error
      subject.__bound?.should be_false
    end
    it 'should allow binding to another thread' do
      expect { subject.__bind_to_thread(Thread.current) }.
        not_to raise_error
      subject.__bound?.should be_true
    end
  end

  context 'when nullbound' do
    subject do
      clazz.new(obj)
    end
    before do
      subject.__nullbind
    end
    it 'should not be bound' do
      subject.__bound?.should be_false
    end
    it 'should not allow messages' do
      expect { subject.foo }.
        to raise_error(ZeevexConcurrency::BindingError)
    end
    it 'should remain nullbound after message' do
      expect { subject.foo }.
        to raise_error(ZeevexConcurrency::BindingError)
      subject.__bound?.should be_false
    end
    it 'should allow unbinding' do
      expect { subject.__unbind }.
        not_to raise_error
    end
    it 'should allow nullbinding' do
      expect { subject.__nullbind }.
        not_to raise_error
    end
    it 'should allow binding to another thread' do
      expect { subject.__bind_to_thread(Thread.current) }.
        not_to raise_error
    end
  end

  context 'class methods' do
    it '.bind should call __bind_to_thread__ on object' do
      obj.should_receive(:__bind_to_thread).with(thread)
      clazz.bind(obj, thread)
    end

    it '.unbind should call __unbind on object' do
      obj.should_receive(:__unbind)
      clazz.unbind(obj)
    end

    it '.nullbind should call __nullbind on object' do
      obj.should_receive(:__nullbind)
      clazz.nullbind(obj)
    end

    it '.bound? should call __bound? on object' do
      obj.should_receive(:__bound?)
      clazz.bound?(obj)
    end
  end

end


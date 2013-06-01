require File.expand_path(File.join(File.dirname(__FILE__), '../spec_helper'))
require 'zeevex_concurrency/locks/synchronized.rb'
require 'thread'

describe ZeevexConcurrency::Synchronized do
  clazz = ZeevexConcurrency::Synchronized
  let :mockobj do
    mock('Foo')
  end
  subject do
    clazz.new(mockobj)
  end

  def is_a_synchronized_object(obj)
    obj.should_not be_nil
    obj.respond_to?(:__getobj__).should be_true
  end

  context 'creation' do
    context '#new' do
      it 'should accept an object' do
        is_a_synchronized_object(subject).should be_true
      end
      it 'should accept an object and mutex' do
        is_a_synchronized_object( clazz.new(mockobj, ::Mutex.new) ).should be_true
      end
      it 'should create a Synchronized object' do
        is_a_synchronized_object(subject).should be_true
      end
    end

    context 'factory method' do
      it 'should exist as ZeevexConcurrency::Synchronized()' do
        ZeevexConcurrency.should respond_to(:Synchronized)
      end
      it 'should create a synchronized object' do
        is_a_synchronized_object( ZeevexConcurrency::Synchronized(mockobj) ).should be_true
      end
      it 'should accept an optional mutex' do
        is_a_synchronized_object( ZeevexConcurrency::Synchronized(mockobj, ::Mutex.new) ).should be_true
      end
    end
  end

  context 'book-keeping' do
    it 'should return the wrapped object if asked' do
      subject.__getobj__.should == mockobj
    end

  end

  context 'as proxy' do
    it 'should not forward __send__ and __getobj__ to the wrapped object' do
      subject.__send__(:__getobj__)
    end
    it 'should forward all other messages to the wrapped object' do
      methods = [:bar, :class, :respond_to?]
      methods.each {|meth| mockobj.should_receive(meth)}
      subject.bar
      subject.class
      subject.respond_to?(:x)
      subject.__send__(:__getobj__)
    end
    it 'should perform self-replacement with the proxy' do
      mockobj.should_receive(:bar).and_return(mockobj)
      subject.bar.__id__.should == subject.__id__
    end
    it 'should wrap all method calls on the object in a synchronized block' do
      mutex = mock('Muteks')
      mutex.should_receive(:synchronize)
      clazz.new(mockobj, mutex).doit
    end
  end

  context 'with user-supplied mutexes' do
    it 'should work with a user-supplied synchronizer instead of a Mutex' do
      mutex = mock('Muteks')
      mutex.should_receive(:synchronize) do |&block|
        block.call
      end
      mockobj.should_receive :chekkit
      clazz.new(mockobj, mutex).chekkit
    end
  end

  context 'Marshalled' do
    subject do
      Marshal.dump clazz.new("foobar")
    end
    it { should be_a(String) }
    it 'should deserialize to a properly proxied underlying object' do
      Marshal.load(subject).should == "foobar"
    end
    it 'should deserialize as a Synchronized object' do
      is_a_synchronized_object(  Marshal.load(subject) ).should be_true
    end
  end
end

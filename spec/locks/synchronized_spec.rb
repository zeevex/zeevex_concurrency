require File.join(File.dirname(__FILE__), '../spec_helper')
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
  context 'creation' do
    context '#new' do
      it 'should accept an object' do
        clazz.new(mockobj).should_not be_nil
      end
      it 'should accept an object and mutex' do
        clazz.new(mockobj, ::Mutex.new).should_not be_nil
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
        mutex.should_receive(:synchronize)
        clazz.new(mockobj, mutex).chekkit
      end
    end

    context 'Marshalled' do
      subject do
        Marshal.dump clazz.new("foobar")
      end
      it { should be_a(String) }
      it 'should deserialize as the underlying object' do
        Marshal.load(subject).should == "foobar"
      end
    end
  end

end

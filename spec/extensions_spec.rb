require File.join(File.dirname(__FILE__), 'spec_helper')
require 'zeevex_concurrency/extensions.rb'
require 'thread'

describe ZeevexConcurrency::Synchronized do
  let :loop do
    loop = ZeevexConcurrency::ThreadPool::FixedPool.new(1)
  end

  # Optional `concurrency` argument is interpreted thusly:
  #
  # positive integer:   use a new pool with up to that many threads (no more than length of list)
  # no / nil argument:  use a new pool with default number of threads (2 * cpu_count)
  # -1:                 use the default Future thread pool
  # 0 or INT_MAX:       use exactly as many threads as length of list (fully concurrent)
  # pool or event_loop: use the provided executor

  context 'ZeevexConcurrency.thread_pool_from_spec' do
    it 'should treat nil as 2*CPU' do
      ZeevexConcurrency::ThreadPool::FixedPool.should_receive(:new).with()
      ZeevexConcurrency.thread_pool_from_spec nil
    end
    it 'should treat -1 argument as using the default pool' do
      ZeevexConcurrency::ThreadPool::FixedPool.should_not_receive(:new)
      ZeevexConcurrency::Future.should_receive :worker_pool
      ZeevexConcurrency.thread_pool_from_spec -1
    end
    it 'should treat -1 argument as using the supplied default pool' do
      ZeevexConcurrency::ThreadPool::FixedPool.should_not_receive(:new)
      ZeevexConcurrency::Future.should_not_receive :worker_pool
      pool = Object.new
      ZeevexConcurrency.thread_pool_from_spec(-1, pool).should == pool
    end
    it 'should treat 0 as fully concurrent processing of all elements' do
      ZeevexConcurrency::ThreadPool::FixedPool.should_receive(:new).with(100)
      ZeevexConcurrency.thread_pool_from_spec 0, nil, 100
    end
    it 'should accept and use a thread pool' do
      pool = ZeevexConcurrency::ThreadPool::FixedPool.new(1)
      ZeevexConcurrency.thread_pool_from_spec(pool).should == pool
    end
  end

  context 'ZeevexConcurrency.greedy_pmap' do
    context 'argument parsing' do
      it 'should require a collection as first arg' do
        expect { ZeevexConcurrency.greedy_pmap(nil) { |x| x } }.to raise_error(ArgumentError)
      end
      it 'should require a block' do
        expect { ZeevexConcurrency.greedy_pmap([1,2,3]) }.to raise_error(ArgumentError)
      end
    end
  end

  shared_examples_for 'collection with pmap' do
    it { should respond_to(:pmap) }
    it 'should yield a result of equal length' do
      subject.pmap {|x| x}.length.should == subject.length
    end
  end

  context 'Array#pmap' do
    subject { [1,2,3] }
    it_should_behave_like 'collection with pmap'
    it 'should process collection properly' do
      subject.pmap {|x| x*2}.should == [2,4,6]
    end
  end

  context 'Hash#pmap' do
    subject { {:a => 1, :b => 33} }
    it_should_behave_like 'collection with pmap'
    it 'should process collection properly' do
      Hash[subject.pmap {|(k,v)| [k.to_s, v+100]}].should == {"a" => 101, "b" => 133}
    end
  end

  context 'Set#pmap' do
    subject { [99, 230, 500] }
    it_should_behave_like 'collection with pmap'
    it 'should process collection properly' do
      subject.pmap {|v| 1000+v}.to_set.should == Set.new([1500, 1230, 1099])
    end
  end
end

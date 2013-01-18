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

  context 'ZeevexConcurrency.greedy_pmap' do
    context 'argument parsing' do
      it 'should require a collection as first arg'
      it 'should require a block'
    end

    context 'concurrency argument parsing' do
      it 'should treat no argument as 2*CPU'
      it 'should treat nil argument as 2*CPU'
      it 'should treat -1 argument as using the default pool'
      it 'should treat 0 as fully concurrent processing of all elements'
      it 'should accept and use a thread pool'
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
  end

  context 'Hash#pmap' do
    subject { {:a => 1, :b => 33} }
    it_should_behave_like 'collection with pmap'
  end

  # context 'Enumerable#pmap' do
  #   subject { Enumerable }
  #   it_should_behave_like 'collection class with pmap'
  # end
end

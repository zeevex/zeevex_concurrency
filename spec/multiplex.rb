require File.join(File.dirname(__FILE__), 'spec_helper')
require 'zeevex_concurrency/future.rb'
require 'zeevex_concurrency/multiplex.rb'
require 'set'

#
# this test counts on a single-threaded worker pool
#
describe ZeevexConcurrency::Multiplex do

  let :queue do
    Queue.new
  end

  let :loop do
    loop = ZeevexConcurrency::ThreadPool::FixedPool.new(1)
  end

  before :each do
    pause_queue
    queue
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

  before do
    @futures = [*1..4].map do |x|
      ZeevexConcurrency::Future.create { queue.pop }
    end
    subject
  end
  clazz = ZeevexConcurrency::Multiplex

  context 'multiplex::first' do


    subject { clazz.new(@futures, 1) }

    it 'should not be ready if no futures are ready' do
      subject.ready?.should be_false
    end

    it 'should provide access to the set of unfinished futures before any have completed' do
      subject.dependencies.should == @futures
    end

    it 'should provide access to the set of unfinished futures before any have completed' do
      subject.waiting.should == @futures
    end

    it 'should be ready if one future is ready' do
      queue << 1
      subject.wait(1).should be_true
    end

    it 'should return the first future to complete in a list' do
      queue << 1
      subject.value.should == [@futures.first]
    end

    it 'should provide persistent access to the returned futures in #value' do
      queue << 1
      subject.value
      subject.value.should == [@futures.first]
    end

    it 'should provide access to the set of unfinished futures after one has completed' do
      queue << 1
      subject.value
      subject.waiting.should == @futures[1..-1]
    end
  end

  context 'multiplex::all' do
    clazz = ZeevexConcurrency::Multiplex

    subject { clazz.new(@futures, @futures.length) }

    it 'should not be ready if no futures are ready' do
      subject.ready?.should be_false
    end

    it 'should not be ready if two futures are ready' do
      2.times { queue << 1 }
      @futures[0].wait
      @futures[1].wait
      subject.ready?.should be_false
    end

    it 'should provide access to the set of dependent futures before any have completed' do
      subject.dependencies.should == @futures
    end

    it 'should provide access to the set of unfinished futures before any have completed' do
      subject.waiting.should == @futures
    end

    it 'should provide access to the set of unfinished futures after 2 have completed' do
      2.times { queue << 1 }
      @futures[0].wait
      @futures[1].wait
      @futures[2].wait(0.1)
      subject.waiting.size.should == 2
    end

    it 'should provide access to the set of completed futures after 2 have completed' do
      2.times { queue << 1 }
      @futures[0].wait
      @futures[1].wait
      @futures[2].wait(0.1)
      subject.complete.size.should == 2
    end

    it 'should be ready if all futures are ready' do
      4.times { queue << 1 }
      subject.wait(1).should be_true
    end

    it 'should return all completed futures in a list when done' do
      4.times { queue << 1 }
      Set.new(subject.value).should == Set.new(@futures)
    end

    it 'should provide persistent access to the returned futures in #value' do
      4.times { queue << 1 }
      Set.new(subject.value).should == Set.new(@futures)
      Set.new(subject.value).should == Set.new(@futures)
    end

    it 'should provide access to the set of unfinished futures after one has completed' do
      3.times { queue << 1 }
      subject.wait(1).should == false
    end
  end

end


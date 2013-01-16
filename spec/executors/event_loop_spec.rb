require File.join(File.dirname(__FILE__), '../spec_helper')
require 'zeevex_concurrency/deferred/promise.rb'
require 'zeevex_concurrency/executors/event_loop.rb'

describe ZeevexConcurrency::EventLoop do
  let :loop do
    ZeevexConcurrency::EventLoop.new
  end
  before do
    loop.start
  end
  let :queue do
    Queue.new
  end

  before do
    queue
  end

  around :each do |ex|
    Timeout::timeout(15) do
      ex.run
    end
  end

  context 'basic usage' do
    it 'should allow enqueue of a proc' do
      loop.enqueue(Proc.new { true }).should be_a(ZeevexConcurrency::Promise)
    end

    it 'should allow enqueue of a block' do
      loop.enqueue do
        true
      end.should be_a(ZeevexConcurrency::Promise)
    end

    it 'should allow enqueue of a Promise, and return same promise' do
      promise = ZeevexConcurrency::Promise.new(Proc.new {true})
      loop.enqueue(promise).should == promise
    end
  end

  context 'running tasks asynchronously' do


    it 'should execute the task on the event loop' do
      loop.enqueue { queue << Thread.current.__id__ }
      queue.pop.should_not == Thread.current.__id__
    end

    it 'should return the callable\'s value in the returned promise' do
      res = loop.enqueue { 100 * 2 }
      res.value.should == 200
    end

    it 'should update the promise only when ready' do
      res = loop.enqueue { queue.pop; "foo" }
      res.should_not be_ready
      queue << "go ahead"
      res.value.should == "foo"
    end

    it 'should allow enqueueing from the event loop, and execute in order' do
      loop.enqueue do
        # runs after this block finishes
        loop.enqueue { queue << "val2" }
        queue << "val1"
      end
      [queue.pop, queue.pop].should == ["val1", "val2"]
    end
  end

  context '#on_event_loop' do
    it 'should execute the task asynchronously from client code' do
      loop.on_event_loop { queue << Thread.current.__id__ }.wait
      queue.pop.should_not == Thread.current.__id__
    end

    it 'should execute the task synchronously when called from event loop' do
      loop.enqueue do
        loop.on_event_loop { queue << "foo" }
        res = queue.pop
        queue << "done"
      end.wait
      queue.pop.should == "done"
    end
  end

  context '#run_and_wait' do
    it 'should not return a promise, but the result of the computation' do
      loop.run_and_wait { queue }.should == queue
    end

    it 'should execute the task on a different thread from client code' do
      loop.run_and_wait { queue << Thread.current.__id__ }
      queue.pop.should_not == Thread.current.__id__
    end

    it 'should execute the task synchronously when called from event loop' do
      res = loop.run_and_wait do
        loop.run_and_wait { queue << "foo" }
        queue << "done"
        queue.pop.should == "foo"
        "hey"
      end
      queue.pop.should == "done"
      res.should == "hey"
    end
  end

  context 'null event loop' do
    let :loop do
      ZeevexConcurrency::EventLoop::Null.new
    end

    it 'should not run the callable provided' do
      foo = 100
      promise = loop.enqueue do
        foo += 1
      end
      promise.should be_ready
      foo.should == 100
    end

    it 'should return nil in the promise' do
      promise = loop.enqueue do
        75
      end
      promise.should be_ready
      promise.value.should be_nil
    end
  end

  context 'inline event loop' do
    let :loop do
      ZeevexConcurrency::EventLoop::Inline.new
    end

    it 'should run the callable provided' do
      Thread.exclusive do
        foo = 100
        promise = loop.enqueue do
          foo += 1
        end
        promise.should be_ready
        foo.should == 101
      end
    end

    it 'should return the value in the promise' do
      Thread.exclusive do
        promise = loop.enqueue do
          75
        end
        promise.should be_ready
        promise.value.should == 75
      end
    end
  end
end


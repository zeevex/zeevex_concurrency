require File.join(File.dirname(__FILE__), '../spec_helper')
require 'zeevex_concurrency/future.rb'
require 'zeevex_concurrency/dataflow.rb'
require 'zeevex_concurrency/event_loop.rb'
require 'zeevex_concurrency/thread_pool.rb'

#
# this test counts on a single-threaded worker pool
#
describe 'Dataflow variables' do

  Promise = ZeevexConcurrency::Promise
  Future  = ZeevexConcurrency::Future
  Dataflow = ZeevexConcurrency::Dataflow

  let :result do
    mock()
  end

  before :each do
    loop = ZeevexConcurrency::ThreadPool::ThreadPerJobPool.new
    ZeevexConcurrency::Future.worker_pool = loop
  end

  context 'conversion method' do
    it 'should exist in Future' do
      Future.create { 1 }.should respond_to(:to_dataflow)
    end
    it 'should exist in Promise' do
      Promise.create.should respond_to(:to_dataflow)
    end
  end

  context 'creating' do
    context 'from promises' do
      let :promise do
        Promise.create
      end
      subject do
        promise.to_dataflow
      end
      before do
        promise
        subject
      end
      it 'should produce a dataflow variable' do
        Dataflow.is_dataflow?(subject).should be_true
      end
      it 'should unify when the promise is fulfilled' do
        t = Thread.new { @x = subject + 10 }
        sleep 0.1
        @x.should be_nil
        promise << 22
        t.join
        @x.should == 32
      end
    end

    context 'from futures' do
      let :future do
        Future.create do
          sleep 0.2
          5
        end
      end

      subject do
        future.to_dataflow
      end

      #before do
      #  future
      #  subject
      #end

      it 'should produce a dataflow variable' do
        Dataflow.is_dataflow?(subject).should be_true
      end

      it 'should unify when the future completes' do
        x = subject + 10
        future.should be_ready
        x.should == 15
      end
    end
  end

  context 'blocking behavior'

  context 'invocation of methods on result object' do
    subject do
        Future.create { result }.to_dataflow
    end

    it 'should forward non-standard methods' do
      result.should_receive(:blahblah)
      subject.blahblah
    end

    it 'should forward standard methods' do
      result.should_receive(:class).and_return(73)
      subject.class.should == 73
    end
  end

end


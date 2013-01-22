require File.join(File.dirname(__FILE__), '../spec_helper')
require 'zeevex_concurrency/util/refcount.rb'
require 'thread'

describe ZeevexConcurrency::Util::Refcount do
  class Refcounted
    include ZeevexConcurrency::Util::Refcount

    def initialize(&destroy_proc)
      @destroy_proc = destroy_proc
      _initialize_refcount
    end

    def destroy
      @destroy_proc.call if @destroy_proc
    end

    def get_refcount
      @_refcount.value
    end
  end

  let :obj do
    mock()
  end

  context 'initialization' do
    it 'should begin with a refcount of 0' do
      Refcounted.new(&lambda {}).refcount.should == 0
    end
    it 'should NOT call destroy at initialization' do
      Refcounted.new(&lambda {obj.blowup})
    end
  end

  context 'retrieving refcount' do
    subject do
      Refcounted.new(&lambda {obj.blowup})
    end
    it 'should just return refcount when given 0 arg' do
      subject.refcount(0).should == 0
    end
    it 'should just return refcount when given nil arg' do
      subject.refcount(nil).should == 0
    end
    it 'should just return refcount when given no arg' do
      subject.refcount.should == 0
    end
    it 'should NOT call destroy when retrieving refcount of 0' do
      obj.should_not_receive(:blowup)
      subject.refcount
    end
  end

  context 'calling refcount with non-zero integer ' do
    subject do
      Refcounted.new(&lambda {obj.blowup}).retain
    end
    it 'should return resulting refcount after alteration' do
      subject.refcount(1).should == 2
    end
    it 'should alter refcount by positive amount' do
      expect { subject.refcount(2) }.
        to change { subject.refcount }.by 2
    end
    it 'should alter refcount by negative amount' do
      subject.refcount(2)
      expect { subject.refcount(-2) }.
        to change { subject.refcount }.by -2
    end
    it 'should call #destroy when refcount reaches 0' do
      obj.should_receive(:blowup)
      subject.refcount(-1)
    end
  end

  context '#retain' do
    subject do
      Refcounted.new(&lambda {obj.blowup}).retain
    end
    it 'should increase refcount by 1' do
      expect { subject.retain }.
        to change { subject.refcount }.by 1
    end
    it 'should call refcount(1)' do
      subject.should_receive(:refcount).with(1)
      subject.retain
    end
    it 'should return object' do
      subject.retain.should == subject
    end
  end

  context '#release' do
    subject do
      Refcounted.new(&lambda {obj.blowup}).retain.retain
    end
    it 'should decrease refcount by 1' do
      expect { subject.release }.
        to change { subject.refcount }.by -1
    end
    it 'should call refcount(-1)' do
      subject.should_receive(:refcount).with(-1)
      subject.release
    end
    it 'should return object' do
      subject.release.should == subject
    end
  end

  context 'sanity checking' do
    it 'should raise exception if refcount is adjusted to less than 0' do
      expect { Refcounted.new(&lambda {}).release }.to raise_error
    end
  end

  context '#with_reference' do
    subject do
      Refcounted.new(&lambda {obj.blowup})
    end
    it 'should increase refcount before calling block and decrease after calling block' do
      subject.retain
      subject.with_reference do
        subject.refcount.should == 2
      end
      subject.refcount.should == 1
    end
    it 'should destroy object at end if called on object with 0 refcount' do
      obj.should_receive(:in_block)
      obj.should_receive(:blowup)
      subject.with_reference do
        obj.in_block
      end
    end
    it 'should call block with self as param' do
      subject.retain
      obj.should_receive(:called)
      subject.with_reference do |ref|
        obj.called
        ref.should == subject
      end
    end
  end

end


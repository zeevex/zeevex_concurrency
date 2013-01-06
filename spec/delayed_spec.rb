require File.join(File.dirname(__FILE__), 'spec_helper')
require 'zeevex_concurrency/delayed.rb'
require 'zeevex_concurrency/promise.rb'
require 'zeevex_concurrency/future.rb'
require 'zeevex_concurrency/delay.rb'

describe ZeevexConcurrency::Delayed do
  clazz = ZeevexConcurrency

  context 'creation' do
    context '#promise' do
      it 'should create a promise with a block' do
        clazz.promise do
        end.should be_a(ZeevexConcurrency::Promise)
      end

      it 'should create a promise with no arg or block' do
        clazz.promise.should be_a(ZeevexConcurrency::Promise)
      end
    end

    context '#future' do
      it 'should create a future' do
        clazz.future do
        end.should be_a(ZeevexConcurrency::Future)
      end
    end

    context '#delay' do
      it 'should create a delay given a block' do
        clazz.delay do
        end.should be_a(ZeevexConcurrency::Delay)
      end
    end
  end

  context 'typing' do
    let :efuture do
      ZeevexConcurrency.future(Proc.new {})
    end
    let :epromise do
      ZeevexConcurrency.promise(Proc.new {})
    end
    let :edelay do 
      ZeevexConcurrency.delay(Proc.new {})
    end
    let :eproc do
      Proc.new {}
    end
    context '#delayed?' do
      it 'should be true for a promise' do
        clazz.delayed?(epromise).should be_true
      end
      it 'should be true for a future' do
        clazz.delayed?(efuture).should be_true
      end
      it 'should be true for a delay' do
        clazz.delayed?(edelay).should be_true
      end
      it 'should not be true for a proc' do
        clazz.delayed?(eproc).should be_false
      end
    end

    context '#future?' do
      it 'should be true for a future' do
        clazz.future?(efuture).should be_true
      end

      it 'should be false for a promise' do
        clazz.future?(epromise).should be_false
      end

      it 'should be false for a delay' do
        clazz.future?(edelay).should be_false
      end
    end

    context '#promise?' do
      it 'should be true for a promise' do
        clazz.promise?(epromise).should be_true
      end
      it 'should be false for a future' do
        clazz.promise?(efuture).should be_false
      end
      it 'should be false for a delay' do
        clazz.promise?(edelay).should be_false
      end
    end

    context '#delay?' do
      it 'should be true for a delay' do
        clazz.delay?(edelay).should be_true
      end
      it 'should be false for a promise' do
        clazz.delay?(epromise).should be_false
      end
      it 'should be false for a future' do
        clazz.delay?(efuture).should be_false
      end
    end
  end
end


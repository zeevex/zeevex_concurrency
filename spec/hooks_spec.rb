require File.join(File.dirname(__FILE__), 'spec_helper')
require 'zeevex_concurrency/hooks.rb'

describe ZeevexConcurrency::Hooks do
  class HookableClass
    include ZeevexConcurrency::Hooks

    def initialize
      _initialize_hook_module
    end
  end

  let :loop do
    ZeevexConcurrency::EventLoop.new
  end
  before do
    loop.start
  end

  subject { HookableClass.new }

  let :receiver do
    Object.new
  end

  context 'argument checking' do
    it 'should require a callable or block' do
      expect { subject.add_hook(:foo, nil) }.
        to raise_error(ArgumentError)
    end

    it 'should accept a proc' do
      expect { subject.add_hook(:foo, Proc.new {}) }.
        not_to raise_error(ArgumentError)
    end

    it 'should accept a block' do
      expect {
        subject.add_hook(:foo) do
          1
        end
      }.not_to raise_error(ArgumentError)
    end
  end

  context 'basic hook usage' do
    it 'should call provided proc' do
      receiver.should_receive(:process)
      subject.add_hook(:foo, Proc.new {receiver.process})
      subject.run_hook :foo
    end

    it 'should call provided block' do
      receiver.should_receive(:process)
      subject.add_hook(:foo) do |obj|
        receiver.process
      end
      subject.run_hook :foo
    end

    it 'should invoke call if handed a non-Proc callable' do
      receiver.should_receive(:call).with(subject, 50)
      subject.add_hook(:foo, receiver)
      subject.run_hook :foo, 50
    end

    it 'should allow hook to be removed' do
      receiver.should_not_receive(:call)
      identifier = subject.add_hook(:foo, receiver)
      subject.remove_hook(:foo, identifier)
      subject.run_hook :foo, 50
    end

    it 'should return identifier for a hook' do
      subject.add_hook(:foo, receiver).should_not be_nil
    end

    it 'should return number identifier for an unnamed hook' do
      subject.add_hook(:foo, receiver).should be_a(Numeric)
    end

    it 'should return unique identifier for each hook added' do
      subject.add_hook(:foo, receiver).should_not ==
          subject.add_hook(:foo, receiver)
    end

    it 'should return user-provided identifier' do
      subject.add_hook(:foo, receiver, :identifier => "foobarbaz").should == "foobarbaz"
    end

    it 'should allow hook to be removed by user-provided identifier' do
      receiver.should_not_receive(:call)
      subject.add_hook(:foo, receiver, :identifier => "foobarbaz")
      subject.remove_hook(:foo, "foobarbaz")
      subject.run_hook :foo, 50
    end

    it 'should allow multiple hooks to be added and run with a given identifier' do
      receiver.should_receive(:call).twice
      subject.add_hook(:foo, receiver, :identifier => "foobarbaz")
      subject.add_hook(:foo, receiver, :identifier => "foobarbaz")
      subject.run_hook :foo, 50
    end

    it 'should allow all hooks with a given identifier to be removed at once' do
      receiver.should_not_receive(:call)
      subject.add_hook(:foo, receiver, :identifier => "foobarbaz")
      subject.add_hook(:foo, receiver, :identifier => "foobarbaz")
      subject.remove_hook(:foo, "foobarbaz")
      subject.run_hook :foo, 50
    end
  end

  context 'observers' do
    it "should call provided proc" do
      receiver.should_receive(:process).with(:foo, subject)
      subject.add_hook_observer(Proc.new { |*args| receiver.process(*args) })
      subject.run_hook :foo
    end

    it "should call provided block" do
      receiver.should_receive(:process)
      subject.add_hook_observer do |*args|
        receiver.process(*args)
      end
      subject.run_hook :foo
    end

    it "should invoke call if handed a non-Proc callable" do
      receiver.should_receive(:call).with(:foo, subject, 50)
      subject.add_hook_observer(receiver)
      subject.run_hook :foo, 50
    end

    it "should allow observer to be removed" do
      receiver.should_not_receive(:call)
      identifier = subject.add_hook_observer(receiver)
      subject.remove_hook_observer(identifier)
      subject.run_hook :foo, 50
    end
  end

  context 'event loops' do
    before do
      loop.should_receive(:enqueue)
    end

    context 'single hook listeners' do
      it 'should enqueue on object-wide loop if present' do
        subject.use_run_loop_for_hooks(loop)
        subject.add_hook(:foo, Proc.new {})
        subject.run_hook :foo
      end

      it 'should enqueue on provided loop in options' do
        subject.add_hook(:foo, Proc.new {}, :eventloop => loop)
        subject.run_hook :foo
      end

      it 'should enqueue on provided loop in options even if object-wide loop provided' do
        subject.use_run_loop_for_hooks(Object.new)
        subject.add_hook(:foo, Proc.new {}, :eventloop => loop)
        subject.run_hook :foo
      end
    end

    context 'observers' do
      it 'should enqueue on object-wide loop if present' do
        subject.use_run_loop_for_hooks(loop)
        subject.add_hook_observer(Proc.new {})
        subject.run_hook :foo
      end

      it 'should enqueue on provided loop in options' do
        subject.add_hook_observer(Proc.new {}, :eventloop => loop)
        subject.run_hook :foo
      end

      it 'should enqueue on provided loop in options even if object-wide loop provided' do
        subject.use_run_loop_for_hooks(Object.new)
        subject.add_hook_observer(Proc.new {}, :eventloop => loop)
        subject.run_hook :foo
      end
    end
  end

  context 'with pre-args'
end


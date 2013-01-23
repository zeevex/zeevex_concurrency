require File.join(File.dirname(__FILE__), '../spec_helper')
require 'zeevex_concurrency/util/platform.rb'
require 'thread'

describe ZeevexConcurrency::Util::Platform do
  clazz = ZeevexConcurrency::Util::Platform
  def pretend_yarv
    stub_const("RUBY_ENGINE", "ruby")
    stub_const('RUBY_VERSION', '1.9.2')
  end

  def pretend_mri_18
    stub_const('RUBY_ENGINE', 'ruby')
    stub_const('RUBY_VERSION', '1.8.7')
  end

  def pretend_jruby
    stub_const('RUBY_ENGINE', 'jruby')
    stub_const('RUBY_VERSION', '1.9.3')
    stub_const('JRUBY_VERSION', '1.7.0')
  end

  def pretend_rbx1
    stub_const('RUBY_ENGINE', 'rbx')
    stub_const('RUBY_VERSION', '1.8.7')
    rbobj = mock()
    stub_const('Rubinius', rbobj)
    rbobj.stub(:version).and_return('rubinius 1.2.4 (1.8.7 release 2011-07-05 JI) [x86_64-apple-darwin11.0.0]')
  end

  def pretend_rbx2
    stub_const('RUBY_ENGINE', 'rbx')
    stub_const('RUBY_VERSION', '1.9.3')
    rbobj = mock()
    stub_const('Rubinius', rbobj)
    rbobj.stub(:version).and_return('rubinius 2.0.0rc1 (1.9.3 release 2012-11-02 JI) [x86_64-apple-darwin12.2.1]')
  end

  def pretend_macruby
    stub_const('RUBY_ENGINE', 'macruby')
    stub_const('RUBY_VERSION', '1.9.2')
    stub_const('MACRUBY_VERSION', '0.12')
  end

  def pretend_mruby
    stub_const('RUBY_ENGINE', 'mruby')
    stub_const('RUBY_VERSION', '1.9.2')
  end

  def pretend_rubymotion
    stub_const('RUBY_ENGINE', 'rubymotion')
    stub_const('RUBY_VERSION', '1.9.3')
  end

  def pretend_to_be(platform)
    send "pretend_#{platform}".to_sym
  end

  supported_platforms = [:mri_18, :yarv, :jruby, :rbx1, :rbx2, :macruby]
  unsupported_platforms = [:mruby, :rubymotion]

  before :each do
    ZeevexConcurrency::Util::Platform.send :reset_all
  end

  context '.engine' do
    subject do
      ZeevexConcurrency::Util::Platform.engine
    end
    context 'on MRI 1.9 / YARV' do
      before do
        pretend_yarv
      end
      it 'should return the current Ruby engine' do
        subject[0].should == :yarv
      end
      it 'should return the current Ruby engine version' do
        subject[1].should == '1.9.2'
      end
      it 'should return the current Ruby compatibility version' do
        subject[2].should == '1.9.2'
      end
    end
    context 'on MRI 1.8' do
      before do
        pretend_mri_18
      end
      it 'should return the current Ruby engine' do
        subject[0].should == :mri_18
      end
      it 'should return the current Ruby engine version' do
        subject[1].should == '1.8.7'
      end
      it 'should return the current Ruby compatibility version' do
        subject[2].should == '1.8.7'
      end
    end
    context 'on JRuby' do
      before do
        pretend_jruby
      end
      it 'should return the current Ruby engine' do
        subject[0].should == :jruby
      end
      it 'should return the current Ruby engine version' do
        subject[1].should == '1.7.0'
      end
      it 'should return the current Ruby compatibility version' do
        subject[2].should == '1.9.3'
      end
    end
  end

  context '.features' do
    supported_platforms.each do |platform|
      it 'should return a list of feature names' do
        pretend_to_be platform
        clazz.features.should be_a(Set)
        clazz.features.should_not be_empty
      end
      it 'should return a list of symbols' do
        pretend_to_be platform
        clazz.features.reject {|x| x.is_a?(Symbol) }.should be_empty
      end
    end

    it 'should cache the list at first invocation' do
      clazz.should_receive(:initialize_features).once.and_call_original
      clazz.features
      clazz.features
    end
    it 'should return a frozen copy of the list' do
      clazz.features.should be_frozen
    end
  end

  context '.feature?' do
    before do
      pretend_to_be :mri_18
    end

    it 'should return true if a supported feature is given' do
      clazz.feature?(:threads).should be_true
    end
    it 'should return false if an unsupported feature is given' do
      clazz.feature?(:fibers).should be_false
    end
  end

  context '.assert_supported_platforms!' do
    before do
      pretend_to_be :jruby
    end

    it 'should return true if current platform is supported' do
      clazz.assert_supported_platforms!(:jruby, :yarv).should == true
    end
    it 'should raise NotImplementedError if current platform is not supported' do
      expect { clazz.assert_supported_platforms!(:mri_18, :yarv) }.
        to raise_error(NotImplementedError)
    end
    it 'should execute the provided failure block if current platform is not supported' do
      obj = mock()
      obj.should_receive(:on_platform).with(:jruby)
      clazz.assert_supported_platforms!(:mri_18, :yarv) do |platform|
        obj.on_platform :jruby
      end
    end

  end
end


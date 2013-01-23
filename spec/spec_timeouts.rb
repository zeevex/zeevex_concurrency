require File.join(File.dirname(__FILE__), 'spec_helper')
require 'zeevex_concurrency/extensions.rb'
require 'thread'

describe 'spec timeout tests', :test_timeout => 5 do
  it 'should succeed as a short test' do
    1.should == 1
  end

  it 'should fail as a long test', :test_timeout => 1 do
    1.should == 1
    sleep 10
  end

  it 'should fail with an exception' do
    1.should == 1
    raise "FAYL"
  end

  it 'should fail with a bad expectation' do
    1.should == 2
  end
end

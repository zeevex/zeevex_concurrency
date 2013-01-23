require 'rspec'

$: << File.expand_path(File.dirname(__FILE__) + '../lib')
require 'zeevex_concurrency'

require 'pry'
require 'timeout'
require 'thread'

require File.expand_path(File.dirname(__FILE__) + '/proxy_shared_examples.rb')

RSpec.configure do |config|
  config.before(:suite) do
    puts "Running spec suite on #{RUBY_VERSION}"
  end

  config.around :each do |example|
    completed = false
    name = example.metadata.full_description
    thr = Thread.new do
      sleep 20
      unless completed
        puts "*** Example #{name} is taking too long to run! ***"
      end
    end
    example.run
    completed = true
    thr.kill
  end

  config.before :each do |context|
    example = context.example
    puts "[Running #{example.full_description}]" if ENV['debug'] == 'true'
  end
end

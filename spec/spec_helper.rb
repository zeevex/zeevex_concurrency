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

  config.around :each do |exproc|
    completed = false
    exmetadata = exproc.metadata
    name = exmetadata.full_description
    t_start = Time.now
    thr = Thread.new do
      begin
        result = exproc.run
        [result, nil]
      rescue
        completed = true
        [nil, $!]
      end
    end

    timeout = exmetadata[:test_timeout] || $global_test_timeout || 60

    if thr.join(timeout)
      (result, exception) = thr.value
      raise exception if exception
      result
    else
      runtime = Time.now - t_start
      puts "\n*** Example #{name} at #{example.location} took too long to run (timeout=#{timeout}), DEADLOCK?, aborting test! ***\n"
      Thread.new { timeout(10) { thr.kill } }
      message = "example declared deadlocked after #{timeout} seconds"
      begin
        raise Timeout::Error, message
      rescue
        @example.set_exception($!, message)
      end
    end
  end

  config.before :each do |context|
    example = context.example
    puts "[Running #{example.full_description}]" if ENV['debug'] == 'true'
  end
end

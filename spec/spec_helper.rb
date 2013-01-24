require 'rspec'

$: << File.expand_path(File.dirname(__FILE__) + '../lib')
require 'zeevex_concurrency'

require 'pry'
require 'timeout'
require 'thread'

require File.expand_path(File.dirname(__FILE__) + '/proxy_shared_examples.rb')

puts "RUNNING SPECS ON #{RUBY_DESCRIPTION}" if ENV['debug'] == 'true'

def dump_thread_backtraces(exclude_current=false)
  if defined?(JRuby)
    Process.kill('QUIT', $$)
    ## causing coredumps for me
    # Process.kill('USR2', $$)
    return
  end

  puts "\n---------------------------------\n"
  puts "\nBACKTRACES:\n\n"
  i = 0
  Thread.list.each do |thread|
    i += 1
    next if exclude_current && thread == Thread.current
    puts "\n"
    puts "== Thread #{i} GID=#{thread.group.object_id.to_s(36)} TID-#{thread.object_id.to_s(36)} status=#{thread.status} ==\n"
    puts "  " + thread.backtrace.join("\n  ")
  end
  puts "\n---------------------------------\n"
end

trap 'TTIN' do
  dump_thread_backtraces
end

RSpec.configure do |config|
  config.before(:suite) do
    puts "Running spec suite on #{RUBY_VERSION}"
  end

  $default_repeats = ENV.fetch('test_repeats', 1).to_i
  $global_test_timeout = ENV.fetch('test_timeout', 60).to_i
  
  config.around :each do |exproc|
    puts "[Running #{example.full_description}]" if ENV['debug'] == 'true'

    completed = false
    exmetadata = exproc.metadata
    name = exmetadata.full_description
    repeat = exmetadata.fetch(:repeat, $default_repeats || 1)

    # allow a test case to have repeats disabled
    if repeat == false
      repeat = 1
    end
    if repeat > 1
      puts "REPEATING TEST CASE #{name} #{repeat} times"
    end

    timeout = exmetadata[:test_timeout] || $global_test_timeout || 60

    # if a repeat is not specified in the actual test, multiple its timeout by
    # the repeat count - i.e., we assume that a :repeat-aware test is also
    # setting a total timeout for all its runs, rather than just one

    unless exmetadata[:repeat]
      timeout *= repeat
    end

    t_start = Time.now
    thr = Thread.new do
      begin
        done = false
        while repeat > 0
          result = exproc.run
          res = [result, nil]
          repeat -= 1
        end
        res
      rescue
        completed = true
        [nil, $!]
      end
    end


    if thr.join(timeout)
      (result, exception) = thr.value
      raise exception if exception
      result
    else
      runtime = Time.now - t_start
      puts "\n*** Example #{name} at #{example.location} took too long to run (timeout=#{timeout}), DEADLOCK?, aborting test! ***\n"
      Thread.new { dump_thread_backtraces(true) }
      Thread.new { timeout(10) { thr.kill } }
      message = "example declared deadlocked after #{timeout} seconds"
      begin
        raise Timeout::Error, message
      rescue
        @example.set_exception($!, message)
      end
    end
  end

end

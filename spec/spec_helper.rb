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

  config.around :each do |exproc|
    puts "[Running #{example.full_description}]" if ENV['debug'] == 'true'
    
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
      Thread.new { dump_thread_backtraces(true) }
      Thread.new { timeout(10) { thr.kill } }
      message = "example declared deadlocked after #{timeout} seconds"
      puts "[A]"
      begin
        raise Timeout::Error, message
      rescue
        puts "[B]"
        @example.set_exception($!, message)
        puts "[C]"
      end
      puts "[D]"
    end
  end

end

$: << File.expand_path(File.dirname(__FILE__) + '../lib')
require 'zeevex_concurrency'

require 'pry'
require 'timeout'
require 'thread'
require 'zeevex_concurrency/extensions'
require 'zeevex_concurrency/util/platform'
require 'thread'

require 'benchmark'

puts "Running pmap/map comparison on #{RUBY_DESCRIPTION}"
puts "\n\nStarting thread count = #{Thread.list.size}\n"

def partitioned_map(coll, options = {}, &block)
  parts = ZeevexConcurrency::Util::Platform.cpu_count * 2
  (pool, _) = ZeevexConcurrency.thread_pool_from_spec(parts)
  pool.retain
  batch_size = [(coll.size / parts).ceil, 1].max
  futures = []
  ZeevexConcurrency::Future.with_worker_pool(pool) do
    coll.each_slice(batch_size) do |subcoll|
      if options[:reduce]
        fut = ZeevexConcurrency::Future.create { subcoll.map(&block).reduce(&options[:reduce])  }
      else
        fut = ZeevexConcurrency::Future.create { subcoll.map &block  }
      end
      futures << fut
    end
  end
  futures.flat_map {|chunk| chunk.value }
ensure
  # pool && pool.stop
  pool.release
end

def partitioned_map_zerocopy(coll, options = {}, &block)
  parts = ZeevexConcurrency::Util::Platform.cpu_count * 2
  (pool, _) = ZeevexConcurrency.thread_pool_from_spec(parts)
  batch_size = [(coll.size / parts).ceil, 1].max
  futures = []
  ZeevexConcurrency::Future.with_worker_pool(pool) do
    coll.each_slice(batch_size) do |subcoll|
      if options[:reduce]
        fut = ZeevexConcurrency::Future.create { subcoll.map(&block).reduce(&options[:reduce])  }
      else
        fut = ZeevexConcurrency::Future.create { subcoll.map &block  }
      end

      futures << fut
    end
    futures.flat_map {|chunk| chunk.value }
  end
end

n = (ARGV[0] || 100_000).to_i
@expected = (n+1)*n

puts "for range 1..#{n}, expected result is #{@expected}"

def check(answer)
  raise "#{answer} does not match expected #{@expected}" if answer != @expected
  answer
end

Benchmark.bmbm(10) do |x|
  x.report("parmap:")  do
    check partitioned_map([*(1..n)]) {|x| x*2}.reduce(&:+)
  end
  x.report("parmapred:") do
    res = partitioned_map([*(1..n)], :reduce => lambda {|x,y| x+y }, :initial => 0 ) {|x|  x*2}
    raise "ERROR: size = #{res.size}" if res.size > 32
    sum = res.reduce &:+
    check sum
  end
  x.report("map:")     do
    check [*(1..n)].map {|x| x*2}.reduce(&:+)
  end
  x.report("pmap:") do
    check [*(1..n)].pmap {|x| x*2}.reduce(&:+)
  end  unless ENV['skip_pmap']
end

puts "\n\n** no sum **\n"

Benchmark.bmbm(10) do |x|
  x.report("map:")     { [*(1..n)].map  {|x| x*2} }
  x.report("parmap:")  { partitioned_map([*(1..n)]) {|x|  x*2} }
  unless ENV['skip_pmap']
    x.report("pmap:")    { [*(1..n)].pmap {|x| x*2} }
  end
end

sleep 15

puts "\n\nEnding thread count = #{Thread.list.size}"

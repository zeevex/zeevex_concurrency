#!/usr/bin/env ruby

$:.unshift File.expand_path(File.dirname(__FILE__) + '/../../lib')
require 'ref'

require 'pry'
require 'timeout'
require 'thread'

def assert(cond, str = "Assertion failed")
  raise str unless cond
end


count = (ARGV[0] || 100).to_i

class RefTest
  def to_s
    "the_ref_test_object"
  end
end

$obj = RefTest.new
refq = Ref::ReferenceQueue.new
wref = Ref::WeakReference.new($obj)
#refq.monitor(wref)

while count > 0
  count -= 1
  $obj = nil
  if (qval = refq.shift)
    puts "got qval #{qval.inspect}"
    break
  else
    putc "."
  end
  GC.start
  ObjectSpace.garbage_collect
end

puts

ObjectSpace.each_object(RefTest) do |obj|
  puts "got obj #{obj.__id__}"
end

puts "wref object is: #{wref.object}"

puts "done"

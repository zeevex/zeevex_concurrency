#!/usr/bin/env ruby

$:.unshift File.expand_path(File.dirname(__FILE__) + '/../../lib')
require 'zeevex_concurrency'

# require 'pry'
require 'timeout'

require 'zeevex_concurrency/scope/var'

Var = ZeevexConcurrency::Var

def assert(cond, str = "Assertion failed")
  raise str unless cond
end

count = (ARGV[0] || 10000).to_i

def approach1(count)
  puts "approach #1"
  count.times do
    queue = Queue.new
    subject = Var.new("rootval")
    t1 = Thread.new do
      Var.set(subject, "t1")
      queue.pop
      Var.get(subject)
    end

    Var.with_bindings([[subject, "scopeval"]]) do
      queue << "again"
      assert(t1.value == "t1")
    end
  end
end

def approach2(count)
  puts "approach #2"
  subject2 = Var.new("rootval")
  queue2 = Queue.new

  count.times do
    # failing - expected t1, got rootval on jruby
    t1 = Thread.new do
      Var.set(subject2, "t1")
      queue2.pop
      Var.get(subject2)
    end

    Var.with_bindings([[subject2, "scopeval"]]) do
      queue2 << "again"
      assert(t1.value == "t1")
    end
  end
end

############################################################

def approach3(count)
  puts "approach #3"
  subject3 = Var.new("rootval")
  queue3 = Queue.new
  results = []

  t1 = Thread.new do
    Var.set(subject3, "t1")
    count.times do |i|
      results << Var.get(subject3)
      Thread.pass if i % 5 == 0
    end
    results
  end

  count.times do |i|
    Var.with_bindings([[subject3, "scopeval"]]) do
      Thread.pass if i % 7 == 0
    end
  end

  assert(t1.value.select {|x| x != "t1"}.count == 0)
end

# failing - expected t1, got rootval on jruby

puts "Running #{count} times..."

approach1(count)
approach2(count)
approach3(count)

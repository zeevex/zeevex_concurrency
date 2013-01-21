require 'rspec'

$: << File.expand_path(File.dirname(__FILE__) + '../lib')
require 'zeevex_concurrency'

require 'pry'
require 'timeout'

require File.expand_path(File.dirname(__FILE__) + '/proxy_shared_examples.rb')

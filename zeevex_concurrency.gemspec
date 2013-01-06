# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'zeevex_concurrency/version'

Gem::Specification.new do |gem|
  gem.name          = "zeevex_concurrency"
  gem.version       = ZeevexConcurrency::VERSION
  gem.authors       = ["Robert Sanders"]
  gem.email         = ["robert@zeevex.com"]
  gem.description   = %q{Concurrency utilities including Delays, Promises, Futures, Event Loops, Thread Pools, and Synchronizing wrappers}
  gem.summary       = %q{Some concurrency utilities for Ruby}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency 'zeevex_proxy'
  gem.add_dependency 'countdownlatch', '~> 1.0.0'
  gem.add_dependency 'atomic', '~> 1.0.0'

  ## other headius utils
  # s.add_dependency 'thread_safe'

  gem.add_development_dependency 'rspec', '~> 2.9.0'
  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'pry'
end

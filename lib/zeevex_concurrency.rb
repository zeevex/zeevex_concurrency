require "zeevex_concurrency/version"

module ZeevexConcurrency
  module All
    def self.included(base)
      base.class_eval do
        include ZeevexConcurrency::Logging
      end
    end
  end
  
  def self.logger
    @logger
  end

  def self.logger=(logger)
    @logger = ZeevexConcurrency::Synchronized(logger)
  end
end

require 'thread'
require 'zeevex_concurrency/locks/synchronized'

require 'logger'
require 'zeevex_concurrency/util/nil_logger'

ZeevexConcurrency.logger = ZeevexConcurrency::NilLogger.new

require 'zeevex_concurrency/util/logging'
require 'zeevex_concurrency/executors/event_loop'

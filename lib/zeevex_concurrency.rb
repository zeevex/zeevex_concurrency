require "zeevex_concurrency/version"

module ZeevexConcurrency
  module All
    def self.included(base)
      base.class_eval do
        include ZeevexConcurrency::Hooks
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

require 'zeevex_concurrency/synchronized'

require 'logger'
require 'zeevex_concurrency/nil_logger'

ZeevexConcurrency.logger = ZeevexConcurrency::NilLogger.new

require 'zeevex_concurrency/logging'
require 'zeevex_concurrency/event_loop'
require 'zeevex_concurrency/hooks'


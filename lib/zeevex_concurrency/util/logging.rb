module ZeevexConcurrency
  module Logging
    def logger
      @logger || ZeevexConcurrency.logger
    end
  end
end

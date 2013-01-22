module ZeevexConcurrency
  module Util
    module Logging
      def logger
        @logger || ZeevexConcurrency.logger
      end
    end
  end
end

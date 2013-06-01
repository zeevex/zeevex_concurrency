module ZeevexConcurrency
  module Util
    class NilLogger
      def method_missing(symbol, *args)
        nil
      end
    end
  end
end

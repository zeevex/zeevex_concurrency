require 'zeevex_proxy'

module ZeevexConcurrency
  # this will wait for the promise or future to complete before
  # forwarding the first message
  #
  # TODO: should we use statically Delegated methods where possible?
  #
  class Dataflow < ZeevexProxy::Base
    def method_missing(method, *args, &block)
      result = __getobj__.value.__send__(method, *args, &block)
    end

    def respond_to?(meth)
      sym = meth.to_sym
      return true if [:__is_dataflow?].include?(sym)
      __getobj__.value.__send__(meth)
    end

    def __is_dataflow?
      true
    end

    def self.is_dataflow?(obj)
      obj.respond_to?(:__is_dataflow?)
    end
  end
end

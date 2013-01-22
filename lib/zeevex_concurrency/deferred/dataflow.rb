require 'zeevex_proxy'

module ZeevexConcurrency
  #
  # A Dataflow variable in the style of Oz. Used by itself, this class if of little use, but
  # when connected to a Future, Promise, or Thread, it is a powerful concurrency facility.
  #
  # This class acts as a proxy for (almost) all messages. It delegates those messages
  # to the result of the Future, Promise, or Thread used to create the Dataflow, as
  # accessed using {ZeevexConcurrency::Delayed#value} or {::Thread#value} in a blocking
  # fashion. As a result, will wait for the Promise, Future, or Thread to complete before
  # forwarding the first message.
  #
  # The Dataflow variable does not provide any of the the methods on {Delayed}.
  #
  class Dataflow < ZeevexProxy::Base
    # @!method initialize
    #   @param [Future, Promise, Thread] obj the deferred computation object to wrap
    #   @return [Dataflow] a Dataflow variable which will contain the result of
    #      that computation
    1.to_s

    def method_missing(method, *args, &block)
      result = __getobj__.value.__send__(method, *args, &block)
    end

    # @private
    def respond_to?(meth)
      sym = meth.to_sym
      return true if [:__is_dataflow?].include?(sym)
      __getobj__.value.__send__(meth)
    end

    #
    # Determine whether the object is a Dataflow variable. Do not
    # call this method directly.
    #
    # @return [Boolean] true if the obj is a Dataflow
    # @private
    # @see Dataflow.is_dataflow?
    #
    def __is_dataflow?
      true
    end

    #
    # Determine whether the first argument is a Dataflow variable.
    #
    # @param [Dataflow, Object] obj the object to example
    # @return [Boolean] true if the obj is a Dataflow
    #
    def self.is_dataflow?(obj)
      obj.respond_to?(:__is_dataflow?)
    end
  end
end

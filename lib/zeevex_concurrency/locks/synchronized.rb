# Alex's Ruby threading utilities - taken from https://github.com/alexdowad/showcase

require 'thread'
require 'zeevex_proxy'
require 'zeevex_concurrency'

#
# Wraps an object in a proxy through which all method calls
# will be synchronized.
#
# Uses a Mutex object by default. If
# there is some need for recursive locking (i.e. a proxied
# method call might somehow cause another proxied method call),
# provide a Monitor object to use instead.
#
# The wrapped object can also be set and read out
# which means this can also be used as a thread-safe reference
# (like a 'volatile' variable in Java).
#
# @see ZeevexProxy::Base
# @see __getobj__
# @see __setobj__
#
class ZeevexConcurrency::Synchronized < ZeevexProxy::Base
  #
  # Creates and initializes the synchronizing proxy.
  #
  # @param [Object] obj the object to wrap
  # @param [Mutex, Monitor, nil] mutex if supplied, the Mutex or Monitor to use
  # @return [Synchronized] a Synchronized proxy
  #
  def initialize(obj, mutex = nil)
    super(obj)
    @mutex = mutex || ::Mutex.new
  end

  # @private
  def respond_to?(method)
    __getobj__.respond_to?(method) ||
        [:__getobj__, :marshal_dump, :marshal_load].include?(method.to_sym)
  end

  # @private
  def method_missing(method, *args, &block)
    obj = __getobj__
    result = @mutex.synchronize {
      obj.__send__(method, *args, &block)
    }
    result.__id__ == obj.__id__ ? self : result
  end

  # @private
  def marshal_dump(*args)
    __getobj__
  end

  # @private
  def marshal_load(obj)
    @__proxy_object__ = obj
    @mutex = ::Mutex.new
  end
end

#
# Wrap object with Synchronized unless already wrapped.
#
# @see ZeevexConcurrency::Synchronized#initialize
#
# @param [Object] obj the object to wrap
# @param [Mutex] mutex if supplied, the Mutex or Monitor to use
#
def ZeevexConcurrency.Synchronized(obj, mutex = nil)
  if obj.respond_to?(:__getobj__)
    obj
  else
    ZeevexConcurrency::Synchronized.new(obj, mutex)
  end
end

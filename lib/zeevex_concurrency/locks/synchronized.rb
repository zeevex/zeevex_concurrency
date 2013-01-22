# Alex's Ruby threading utilities - taken from https://github.com/alexdowad/showcase

require 'thread'
require 'zeevex_proxy'
require 'zeevex_concurrency'

# Wraps an object, synchronizes all method calls
# The wrapped object can also be set and read out
#   which means this can also be used as a thread-safe reference
#   (like a 'volatile' variable in Java)
class ZeevexConcurrency::Synchronized < ZeevexProxy::Base
  #
  # Initializes the object.
  #
  # @param [Object] obj the object to wrap
  # @param [Mutex] mutex if supplied, the Mutex or Monitor to use
  def initialize(obj, mutex = nil)
    super(obj)
    @mutex = mutex || ::Mutex.new
  end

  def respond_to?(method)
    __getobj__.respond_to?(method) ||
        [:__getobj__, :marshal_dump, :marshal_load].include?(method.to_sym)
  end

  def method_missing(method, *args, &block)
    obj = __getobj__
    result = @mutex.synchronize {
      obj.__send__(method, *args, &block)
    }
    result.__id__ == obj.__id__ ? self : result
  end

  def marshal_dump(*args)
    __getobj__
  end

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

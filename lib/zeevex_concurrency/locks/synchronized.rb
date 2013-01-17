# Alex's Ruby threading utilities - taken from https://github.com/alexdowad/showcase

require 'thread'
require 'zeevex_proxy'
require 'zeevex_concurrency'

# Wraps an object, synchronizes all method calls
# The wrapped object can also be set and read out
#   which means this can also be used as a thread-safe reference
#   (like a 'volatile' variable in Java)
class ZeevexConcurrency::Synchronized < ZeevexProxy::Base
  def initialize(obj, mutex = nil)
    super(obj)
    @mutex = mutex || ::Mutex.new
    freeze
  end

  def _get_synchronized_object
    @mutex.synchronize { @obj }
  end

  def respond_to?(method)
    @obj.respond_to?(method) ||
        [:_get_synchronized_object].include?(method.to_sym)
  end

  def method_missing(method, *args, &block)
    result = @mutex.synchronize { @obj.__send__(method, *args, &block) }
    result.__id__ == @obj.__id__ ? self : result
  end
end

#
# make object synchronized unless already synchronized
#
def ZeevexConcurrency.Synchronized(obj, mutex = nil)
  if obj.respond_to?(:_get_synchronized_object)
    obj
  else
    ZeevexConcurrency::Synchronized.new(obj, mutex)
  end
end

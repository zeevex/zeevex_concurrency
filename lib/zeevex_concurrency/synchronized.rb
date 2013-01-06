# Alex's Ruby threading utilities - taken from https://github.com/alexdowad/showcase

require 'thread'
require 'zeevex_proxy'

# Wraps an object, synchronizes all method calls
# The wrapped object can also be set and read out
#   which means this can also be used as a thread-safe reference
#   (like a 'volatile' variable in Java)
class ZeevexConcurrency::Synchronized < ZeevexProxy::Base
  def initialize(obj)
    super
    @mutex = ::Mutex.new
  end

  def _set_synchronized_object(val)
    @mutex.synchronize { @obj = val }
  end
  def _get_synchronized_object
    @mutex.synchronize { @obj }
  end

  def respond_to?(method)
    if [:_set_synchronized_object, :_get_synchronized_object].include?(method.to_sym)
      true
    else
      @obj.respond_to?(method)
    end
  end

  def method_missing(method, *args, &block)
    result = @mutex.synchronize { @obj.__send__(method, *args, &block) }
    # result.__id__ == @obj.__id__ ? self : result
  end
end

#
# make object synchronized unless already synchronized
#
def ZeevexConcurrency.Synchronized(obj)
  if obj.respond_to?(:_get_synchronized_object)
    obj
  else
    ZeevexConcurrency::Synchronized.new(obj)
  end
end

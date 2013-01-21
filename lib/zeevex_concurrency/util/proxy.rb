module ZeevexConcurrency
  # let's use a mutated Object for now
  if false && defined?(::BasicObject)
    # A class with no predefined methods that behaves similarly to Builder's
    # BlankSlate. Used for proxy classes.
    class PBasicObject < ::BasicObject
      undef_method :==
      undef_method :equal?

      # Let ActiveSupport::BasicObject at least raise exceptions.
      def raise(*args)
        ::Object.send(:raise, *args)
      end
    end
  else
    class PBasicObject
      KEEP_METHODS = %w[__id__ __send__ method_missing __getobj__ object_id
                        instance_variable_get instance_variable_set instance_variable_defined?
                        remove_instance_variable]

      def self.remove_methods!
        m = (instance_methods.map &:to_s) - KEEP_METHODS
        m.each{|m| undef_method(m)}
      end

      def initialize(*args)
        PBasicObject.remove_methods!
      end

      PBasicObject.remove_methods!
    end
  end

  class Proxy < PBasicObject
    def self.inherited(child)
      child.class_eval { @@_local_instance_vars = [] }
    end

    def initialize(target, options = {}, &block)
      super()
      @obj = @__proxy_object__ = target
      if block
        eigenclass = class << self; self; end
        eigenclass.__send__(:define_method, :method_missing, &block)
      end
    end

    def __getobj__
      @__proxy_object__
    end

    def __substitute_self__(candidate, pself)
      candidate.__id__ == pself.__id__ ? self : candidate
    end

    [:instance_variable_get, :instance_variable_set,
     :instance_variable_defined?, :remove_instance_variable].each do |meth|
      define_method meth do |varname, *args|
        locals = @@_local_instance_vars
        if (locals || []).include?(varname.to_s)
          super(varname, *args)
        else
          __getobj__.__send__(meth, varname, *args)
        end
      end
    end

    # if chainable method or returns "self" for some other reason,
    # return this proxy instead
    def method_missing(name, *args, &block)
      obj = __getobj__
      __substitute_self__(obj.__send__(name, *args, &block), obj)
    end

  end
end

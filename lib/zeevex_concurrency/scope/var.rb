require 'thread'

module ZeevexConcurrency
  class Var < ZeevexProxy::Base
    def self.get(var, *defval)
      var.__getobj__
    rescue ::ZeevexConcurrency::UnboundError
      defval.length > 0 ? defval[0] : raise
    end

    def self.set(var, value)
      b = find_binding(var.__id__) || root_binding
      b[var.__id__] = value
    end

    def self.bound?(var)
      var.__bound?
    end

    def self.thread_bound?(var)
      !! find_binding(var.__id__)
    end

    def self.with_bindings(lets)
      idmap = lets.map {|(k,v)| [k.__id__, v]}
      Var.push_binding( Binding.new(::Hash[idmap]) )
      yield
    ensure
      Var.pop_binding
    end

    def self.set_root(var, val)
      var.__bind_with_value(val)
    end

    protected


    def self.bindings
      ::Thread.current['__zx_var_bindings'] ||= [Binding.new({})]
    end

    def self.find_binding(id)
      bs = bindings
      for x in 1..bs.length
        binding = bs[bs.length - x]
        return binding if binding.include? id
      end
      nil
    end

    def self.root_binding
      bindings[0]
    end

    def self.push_binding(binding)
      bindings.push binding
    end

    def self.pop_binding
      bindings.pop
    end

    public

    def initialize(*args, &block)
      raise ::ArgumentError, 'Only one value is accepted' if args.length > 1

      @mutex = ::Mutex.new
      @bindings = []
      if args.length == 1
        __bind_with_value(args[0])
      elsif block
        __bind_with_block(block)
      end
    end

    def __bind_with_value(value)
      @root_value = value
      @has_root_value  = true
    end

    def __bind_with_block(block)
      @root_proc  = block
    end

    def __getobj__
      b = Var.find_binding(__id__)
      if b
        b[__id__]
      elsif @has_root_value
        @root_value
      elsif @root_proc
        Var.root_binding[__id__] = @root_proc.call
      else
        raise ::ZeevexConcurrency::UnboundError
      end
    end

    def __bound?
      !! (@has_root_value || @root_proc || Var.find_binding(__id__))
    end

    class Binding
      def initialize(val)
        @val = val.dup
      end
      def fetch(key, defval=nil)
        @val.fetch(key, defval)
      end
      def [](key)
        @val[key]
      end
      def []=(key, val)
        @val[key] = val
      end
      def include?(key)
        @val.include?(key)
      end
    end
  end
end

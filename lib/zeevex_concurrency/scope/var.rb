require 'thread'
require 'zeevex_concurrency/util/proxy.rb'

module ZeevexConcurrency
  #
  # This is an attempt to provide a facility similar to Clojure's Vars, though without
  # quite the same "interning" / intertwining with namespaces.
  #
  # A `Var` is a container which contains a reference to a Ruby object.
  # It can be used as a mostly transparent proxy to that object, and the original
  # object can be fetched via Var.get.
  #
  # The main feature of Var is its concurrency semantics.
  #
  # - Each Var may be created with a process-wide default value.
  # - Alternately, it may be created "unbound" with no default value. Unbound vars cannot
  #   be dereferenced and will raise an UnboundError exception if you try.
  # - Finally, a Var may be created with a block, which will be evaluated as needed
  #   to create a per-thread default value.
  #
  # A Var, whether bound or not, can have its global "root value" changed at runtime,
  # though this is discouraged. Such changes affect all threads, though the root value
  # may be shadowed by local bindings.
  #
  # Vars provide a Thread-local data facility through the use of Var.set, e.g.
  #
  #    $somevar = Var.new('foo')
  #    Thread.new { Var.set($somevar, 'threadval'); sleep 5; puts Var.get($somevar) }
  #    puts Var.get($somevar)
  #
  #  Should produce the output:
  #
  #     foo
  #     threadval
  #
  # Vars also provide a dynamic binding facility through the use of Var.with_bindings. Such
  # bindings are similar to dynamic binding in any lisp, though they are visible only to the
  # thread in which they are bound. Again, this is similar to Clojure's Var behavior.
  #
  #    $somevar = Var.new('foo')
  #    Var.with_bindings([[$somevar, 'mainbinding']]) do
  #      puts Var.get($somevar)
  #      Thread.new { puts Var.get($somevar) }.join
  #      Thread.new { Var.set($somevar, 'threadval'); sleep 5; puts Var.get($somevar) }
  #    end
  #    puts Var.get($somevar)
  #
  #  Should produce the output:
  #
  #     mainbinding
  #     foo
  #     foo
  #     threadval
  #
  # Usage:
  #
  # As Vars are generally used as global names (though perhaps with thread-local
  # values), it would be common to assign them to Ruby global variables ($foo) or
  # class variables acting as namespaced globals.  It might also make sense to use them
  # as instance variables in singleton objects where thread-local state is needed.
  #
  #
  class Var < ZeevexConcurrency::Proxy

    def self.get(var, *defval)
      var.__getobj__
    rescue ::ZeevexConcurrency::UnboundError
      defval.length > 0 ? defval[0] : raise
    end

    class << self
      alias_method :deref, :get
    end

    def self.register_thread_root(var, thread)
    end

    def self.set(var, value)
      b = find_binding(var.__id__)
      unless b
        b = root_binding
        register_thread_root(var, ::Thread.current)
      end
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

    # fetch current binding array; autocreate with a single root (non-block-scope-based) binding
    # .set on vars without a block scope binding will use the root binding
    def self.bindings(thr = ::Thread.current)
      thr['__zx_var_bindings'] ||= [Binding.new({})]
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

    @@_local_instance_vars = ["@__weak_backreferences__"]

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

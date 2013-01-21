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
  # Caveats:
  #
  # Thread-local root values are leaky.
  #
  # Instead of using thread-local root/default values, I recommend wrapping code in
  # a `with_bindings` block. Bindings made via `with_bindings` are automatically
  # cleaned up with the block exits, and therefore do not leak (assuming the block
  # ever terminates)
  #
  class Var < ZeevexConcurrency::Proxy

    #
    # Get value of a Var. If unbound, use a supplied default value
    #
    # @overload get(var)
    #   Gets the value of the Var; raises UnboundError if the Var has no value
    #   @param [Var] the Var to dereference
    #   @return [Object] the value, if Var is bound
    #
    # @overload get(var, default_value)
    #   Gets the value of the Var; returns default_value if unbound
    #   @param [Symbol] the Var to dereference
    #   @param [Object] the default value to use if `var` is unbound
    #   @return [Object] the Var's value or default_value
    #
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

    #
    # Set value of a Var to the value. If there is no binding in the current
    # thread, use the root binding frame. If there *is* a binding for the Var
    # as established by e.g. `Var.with_bindings`, it modifies that binding in place.
    #
    # @param [Var] the variable to alter
    # @param [Object] any Ruby object
    # @return [Object] the value that was used
    #
    def self.set(var, value)
      b = find_binding(var.__id__)
      unless b
        b = root_binding
        register_thread_root(var, ::Thread.current)
      end
      b[var.__id__] = value
    end

    #
    # Determine whether this Var can be accessed without raising an UnboundError
    # Note that a Var with a default value proc is considered bound, even though its
    # value has not been calculated
    #
    # @param [Var] the Var to examine
    #
    def self.bound?(var)
      var.__bound?
    end

    #
    # Does this Var have a dynamic or root value binding in this thread?
    #
    # @param [Var] the Var to examine
    #
    def self.thread_bound?(var)
      !! find_binding(var.__id__)
    end

    #
    # Dynamically bind vars to new values for the duration of a block.
    #
    # The `lets` argument should be an Array of 2-tuple arrays of the form [var, value], e.g.
    #
    #     first = Var.new
    #     other = Var.new('baz')
    #     Var.with_bindings([[first, 'boundval'], [other, 'notbaz']]) do
    #       puts Var.get(first)
    #       puts Var.get(other)
    #     end
    #     puts Var.get(first) rescue puts "EXCEPTION"
    #     puts Var.get(other)
    #
    # Should output
    #
    #     boundval
    #     notbaz
    #     EXCEPTION
    #     baz
    #
    #
    # @param [Array] an array of 2-element arrays of the form [Var, value]
    # For a block {|a,b,c| ... }
    # @yield [var1, var2, ...] yields the array of vars as parameters
    # @return [Object] the return value of the block
    #
    def self.with_bindings(lets)
      idmap = lets.map {|(k,v)| [k.__id__, v]}
      Var.push_binding( Binding.new(::Hash[idmap]) )
      yield *lets.map(&:first)
    ensure
      Var.pop_binding
    end

    #
    # Set the global default value of a Var. Affects all threads. Use of this
    # method is discouraged.
    #
    def self.set_root(var, val)
      var.__bind_with_value(val)
    end

    protected

    # fetch current binding array; autocreate with a single root (non-block-scope-based) binding
    # .set on vars without a block scope binding will use the root binding
    def self.bindings(thr = nil)
      thr ||= ::Thread.current
      thr['__zx_var_bindings'] ||= [Binding.new({})]
    end

    #
    # Find the binding for a given Var by *id* (not by the Var object itself)
    #
    def self.find_binding(id)
      bs = bindings
      for x in 1..bs.length
        binding = bs[bs.length - x]
        return binding if binding.include? id
      end
      nil
    end

    #
    # This is the root binding frame for the current Thread by default, or
    # for a given thread if supplied.
    #
    def self.root_binding(thr = nil)
      bindings(thr)[0]
    end

    #
    # Push a Var binding frame onto the thread's stack
    #
    def self.push_binding(binding, thr = nil)
      bindings(thr).push binding
    end

    #
    # Pop a Var binding frame off of the thread's stack
    #
    def self.pop_binding(thr = nil)
      bindings(thr).pop
    end

    public

    #
    # Create a new Var. May be supplied with a single argument to be used as its
    # default value, or a block which will be evaluated to generate the per-thread
    # root value as needed.
    #
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

    protected

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

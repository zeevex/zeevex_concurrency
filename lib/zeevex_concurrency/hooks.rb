module ZeevexConcurrency
    module Hooks
      include ZeevexConcurrency::Logging

      HookCallable = Struct.new(:identifier, :callable, :eventloop, :preargs) do
        def initialize(hash)
          super(*hash.values_at(*self.class.members.map(&:to_sym)) )
          self.preargs    ||= []
          self.identifier ||= self.__id__
        end

        def call(*args)
          if eventloop
            eventloop.enqueue do
              _execute(*args)
            end
          else
            _execute(*args)
          end
        end

        protected

        def _execute(*args)
          arglist = Array(preargs) + Array(args)
          callable.call(*arglist)
        end
      end

      def _initialize_hook_module
        unless @_hook_module_initialized
          @hooks          = {}
          @hook_observers = []
          @_hook_module_initialized = true
        end
      end

      def run_hook(hook_name, *args)
        hook_name = hook_name.to_sym
        logger.debug "<running hook #{hook_name}(#{args.inspect})>"
        if @hooks && @hooks[hook_name]
          Array(@hooks[hook_name]).each do |hook|
            hook.call(self, *args)
          end
        end
        Array(@hook_observers).each do |observer|
          observer.call(hook_name, self, *args)
        end
      end

      #
      # Takes a hash of hook_name_symbol => hooklist
      # hooklist can be a single proc or array of procs
      #
      def add_hooks(hookmap, options = {})
        hookmap.each do |(name, val)|
          Array(val).each do |hook|
            add_hook name.to_sym, hook, options
          end
        end
      end

      def add_hook(hook_name, observer = nil, options = {}, &block)
        @hooks[hook_name] ||= []
        hook = _make_observer(observer || block, options)
        @hooks[hook_name] << hook
        hook.identifier
      end

      def add_hook_observer(observer = nil, options={}, &block)
        hook = _make_observer(observer || block, options)
        @hook_observers << hook
        hook.identifier
      end

      def remove_hook(hook_name, identifier)
        return unless @hooks[hook_name]
        @hooks[hook_name].reject! {|hook| hook.identifier == identifier }
      end

      def remove_hook_observer(identifier)
        @hook_observers.reject! {|hook| hook.identifier == identifier }
      end

      def use_run_loop_for_hooks(runloop)
        @hook_run_loop = runloop
      end

      def _make_observer(callable, options = {})
        raise ArgumentError, "Must provide callable or block" if callable.nil?
        HookCallable.new({:eventloop => @hook_run_loop}.
                             merge(options).
                             merge(:callable => callable)).freeze
      end

    end
end

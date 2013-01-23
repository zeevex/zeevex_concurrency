require 'zeevex_concurrency'
require 'set'

module ZeevexConcurrency
  module Util
    module Platform
      @@features = Set.new

      #
      # Query the platform for support of a feature.
      #
      # @return [Boolean] whether the feature is supported
      #
      def self.feature?(feature)
        features.include? feature.to_sym
      end

      #
      # Query the Ruby runtime for supported language and runtime features.
      #
      # @return [Set<Symbol>] a list of features known to be supported, or detected at runtime.
      #   this will be a frozen array for safety reasons.
      #
      def self.features
        initialize_features unless @@features
        @@features.dup.freeze
      end

      #
      # Using this method, application or library code can indicate the platforms that
      # it supports. It is recommended that library code only raise an exception at
      # a well-defined, optional point, so that application code can continue at its
      # own risk or choose not to test compatibility altogether.
      #
      # @overload assert_supported_platforms!(*platformlist)
      #   @param [Array<Symbol>] An array or varargs list of platforms which the code
      #      is willing to support
      #   @return [Boolean] true if the current platform is contained in the list
      #   @raise NotImplementedError if the current platform is not contained in the list
      #
      # @overload assert_supported_platforms!([platformlist]) { |platform| handler }
      #   @param [Array<Symbol>] An array or varargs list of platforms which the code
      #      is willing to support
      #   @yieldparam [Symbol] the current platform as a symbol, if not in the supported
      #      list
      #   @return [Object] whatever the block returns
      #
      def self.assert_supported_platforms!(platforms, *rest)
        platforms = (Array(platforms) + rest).map &:to_sym
        return true if platforms.include?(engine[0])
        if block_given?
          yield engine[0]
        else
          raise NotImplementedError, "Current platform not in supported list of #{platforms.inspect}"
        end
      end

      #
      # Return information about the current Ruby engine/runtime in a
      # a 3-tuple of the form:
      #    (ruby_engine, engine_version, ruby_lang_compat_version)
      #
      # Known engines (expressed as symbols):
      #
      # :mri_18  :: MRI/CRuby version 1.8.x
      # :yarv    :: MRI/CRuby Ruby 1.9 or later
      # :jruby   :: JRuby; all versions
      # :rbx1    :: Rubinius version 1.x
      # :rbx2    :: Rubinius version 2.x or later
      # :macruby :: MacRuby, any version (tested on 0.12)
      #
      # Unhandled engines: mruby, maglev, rubymotion, ironruby, etc.
      #
      # @return [Array<Symbol, String, String>] a 3-tuple of the form
      #    (ruby_engine, engine_version, ruby_lang_compat_version)
      #
      # @raise NotImplementedError if the engine is not currently supported
      #
      def self.engine
        @@engine ||=
          case RUBY_ENGINE
          when "jruby"
            [:jruby, JRUBY_VERSION, RUBY_VERSION]
          when "ruby"
            [RUBY_VERSION =~ /^1\.8/ ? :mri_18 : :yarv, RUBY_VERSION, RUBY_VERSION]
          when "rbx"
            version = Rubinius.version.match(/rubinius (\S+) \(/)[1]
            [version =~ /^1\./ ? :rbx1 : :rbx2, version, RUBY_VERSION]
          when "macruby"
            [:macruby, MACRUBY_VERSION, RUBY_VERSION]
          when "mruby", "maglev", "rubymotion", "ironruby", "kiji", "opal", "goruby"
            raise NotImplementedError, "Haven't finished support for #{RUBY_ENGINE} yet"
          else
            raise NotImplementedError, "Unknown Ruby Platform: #{RUBY_ENGINE} - #{RUBY_DESCRIPTION}"
          end
      end

      private

      #
      # perform some simple feature detection
      #
      def self.detect_features
        res = []
        res << :threads if defined?(Thread)
        res << :fibers  if defined?(Fiber)
        res += case RUBY_VERSION
               when /^1\.8/ then [:ruby_18]
               when /^1\.9/ then [:ruby_19]
               when /^2\.0/ then [:ruby_19, :ruby_20]
               end
        res << :ree if RUBY_DESCRIPTION.include?("Ruby Enterprise Edition")
        res << :cow_friendly_gc if GC.respond_to?(:copy_on_write_friendly=)
        # TODO - test this on Windows
        res << :fork if Kernel.respond_to?(:fork) && !defined?(JRuby)
        res
      end

      def self.initialize_features
        return if @@features
        (engine, engine_version, compat_version) = self.engine
        @@features = Set.new(
          case engine
          when :jruby
            [:threads, :thread_parallelism, :native_threads, :ruby_18, :ruby_19,
             :ffi, :java, :jit, :aot_compilation, :mvm]
          when :mri_18
            [:threads, :gil, :mri_18, :green_threads, :ruby_18]
          when :yarv
            [:threads, :fibers, :gil, :native_threads, :ruby_19]
          when :rbx1
            [:threads, :rbx, :rubinius, :rbx2, :gil, :green_threads, :ruby_18, :mvm]
          when :rbx2
            # Rubinius has both 1.8 and 1.9 modes (-X18 or -X19)
            mode_features = compat_version.match(/^1\.8/) ? [:ruby_18] : [:ruby_19, :fibers]
            [:threads, :rbx, :rubinius, :thread_parallelism, :native_threads, :jit, :mvm] + mode_features
          when :macruby
            [:threads, :thread_parallelism, :native_threads, :ruby_19,
             :cocoa, :objc, :corefoundation, :osx,
             :aot_compilation, :jit, :dtrace, :grand_central_dispatch, :ffi, :sandbox]
          when :rubymotion
            [:threads, :thread_parallelism, :native_threads, :ruby_19,
             :cocoa, :objc, :corefoundation, :ios,
             :aot_compilation, :dtrace, :grand_central_dispatch, :ffi, :sandbox,
             :refcounting]
          else
            @@features = []
            raise NotImplementedError, "Unsupported Ruby Platform: #{RUBY_ENGINE} - #{RUBY_DESCRIPTION}"
          end)
      end

      def self.reset_all
        @@engine   = nil
        @@features = nil
      end

    end
  end
end

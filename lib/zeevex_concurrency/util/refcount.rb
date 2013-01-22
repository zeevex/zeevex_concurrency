require 'atomic'

module ZeevexConcurrency
  module Util
    #
    # For objects which need strict destructor / finalizer-like behavior beyond
    # that which the Ruby GC can provide, the Refcount mixin provides a simple
    # Objective-C like refcounting interface.
    #
    # A class which includes this mixin MUST implement a {Refcount#destroy} method, which
    # will be called when the object's reference count transitions to 0.
    #
    # The class must also call {#_initialize_refcount} in its initializer.
    #
    # @note Refcounted objects are by default created with a reference count of 0.
    #
    # @abstract include and implement {#destroy} 
    #
    module Refcount
      #
      # Setup the object to be refcounted. By default, objects start with a reference
      # count of 0, and without great provocation that should remain the case.
      #
      # @note This method must be called from the initialize method of any class which
      #    includes the Refcount module
      #
      # @param [Integer] start_count the reference count to initialize with; default 0
      def _initialize_refcount(start_count = 0)
        @_refcount = Atomic.new(start_count)
      end

      #
      # With no arg, nil, or 0 arg, returns current refcount
      # With other arg, alters refcount by that value
      #
      # When refcount transitions to 0, call {Refcount#destroy}.
      #
      # @overload refcount()
      #   Retrieves the current refcount
      #   @return [Integer] the new reference count
      #
      # @overload refcount(offset)
      #   Adjusts the refcount by offset amount (positive or negative)
      #   @param [Integer] offset the amount to adjust refcount by
      #   @return [Integer] the new reference count
      #
      def refcount(offset = nil)
        if offset != nil && offset != 0
          new_count = @_refcount.update {|x| x + offset}
          if new_count == 0
            destroy
          end
          if new_count < 0
            raise IndexError, "Refcount has gone below 0: #{new_count}, offset = #{offset}, obj=#{self.inspect}"
          end
          new_count
        else
          @_refcount.value
        end
      end

      #
      # Increase the reference count of this object by 1.
      #
      # @see #refcount
      def retain
        refcount(1)
        self
      end

      #
      # Decrease the reference count of this object by 1.
      #
      # @see #refcount
      def release
        refcount(-1)
        self
      end

      #
      # Call the block with this object after retaining this object.
      # After the block returns, release this object.  If refcount reaches 0,
      # the object will be destroyed.
      #
      # @note Newly created Refcounted objects have a reference count of 0, which
      #   means that unless they are explicitly retained first, using this method on such
      #   an object will {Refcount#destroy} it after
      #
      # @param [Block] block the block to yield this object to
      # @yieldparam [Refcount] object this object after retaining
      #
      def with_reference(&block)
        retain
        block.call self
      ensure
        release
      end

      # @!method destroy
      #   Called on a Refcounted object when its reference count transitions to 0.
      #   Must be implemented by the Refcounted class.
      #   @abstract
      1.to_s
    end
  end
end

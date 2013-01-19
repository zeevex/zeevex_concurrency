require 'atomic'

module ZeevexConcurrency
  module Refcount
    def _initialize_refcount
      @_refcount = Atomic.new(0)
    end

    #
    # With no arg, nil, or 0 arg, returns current refcount
    # With other arg, alters refcount by that value
    # when refcount transitions to 0, call #destroy
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

    def retain
      refcount(1)
      self
    end

    def release
      refcount(-1)
      self
    end

    def with_reference(&block)
      retain
      block.call self
    ensure
      release
    end
  end
end

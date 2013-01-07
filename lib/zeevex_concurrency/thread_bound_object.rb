require 'zeevex_concurrency'
module ZeevexConcurrency
  class BindingError < StandardError; end

  #
  # This is a wrapper for objects which allows them to be in one of 3 states:
  #
  #  Bound to a thread
  #  Unbound
  #  Nullbound
  #
  # When `unbound`, the object will allow messages from any thread, but will transition
  # to bound(thread_x) after receiving a message from thread_x
  #
  # When in state `bound(thread_x)`, it will *only* accept messages from thread_x. Messages
  # from other threads will cause a BindingError. This includes must binding management
  # messages - in other words, a thread can unbind its own objects; but they cannot be stolen.
  #
  # When in state `nullbound`, it will not allow messages from any thread, other than those
  # associated with binding management.
  #
  class ThreadBoundObject < SimpleDelegator
    #
    # Eagerly bind this object to a thread. If nil or no thread arg provided,
    # binds to current thread
    #
    def self.bind(tbo, thread = nil)
      tbo.__bind_to_thread(thread)
    end

    #
    # Free the object from a binding; will auto-bind to first thread to send
    # it a message
    #
    def self.unbind(tbo)
      tbo.__unbind
    end

    #
    # Prevent the object from receiving messages from ANY thread; used for
    # objects "in transit" between threads, e.g. on a channel or queue
    #
    def self.nullbind(tbo)
      tbo.__nullbind
    end

    def self.bound?(tbo)
      tbo.__bound?
    end

    #
    # Prevent the object from receiving messages from ANY thread; used for
    # objects "in transit" between threads, e.g. on a channel or queue
    #
    #
    def initialize(obj, thread = :unbound)
      super(obj)
      __bind_to_thread(thread) if thread != :unbound
    end

    def __getobj__(ignore_binding = false)
      __check_binding unless ignore_binding
      super()
    end

    def __setobj__(obj)
      raise "__setobj__ not supported"
    end

    #
    # Given no or a nil argument, binds to the current thread
    #
    def __bind_to_thread(thr = nil)
      thr ||= Thread.current
      raise ArgumentError, "Must provide thread" unless thr.is_a?(Thread)
      raise BindingError,  "Object is already bound" if __bound?
      __check_bindability
      @bound_thread_id = thr.__id__
    end

    def __unbind
      __check_bindability
      @bound_thread_id = nil
    end

    #
    # Bind this to a non-existent value so that it cannot be invoked from anywhere;
    # unbind and bind can override this
    #
    def __nullbind
      __check_bindability
      # this can never match Thread.current
      @bound_thread_id = :none
    end

    def __bound?
      @bound_thread_id && @bound_thread_id != :none
    end

    def __bindable?
      @bound_thread_id.nil? || @bound_thread_id == :none
    end

    private


    #
    # Successful if thread unbound or this method is being called from bound thread
    #    if unbound, auto-bind this object to the calling thread
    # raise BindingError otherwise
    #
    def __check_binding
      case @bound_thread_id
      when Thread.current.__id__
        true
      when nil
        @bound_thread_id = Thread.current.__id__
      else
        raise BindingError, "Object is bound to #{@bound_thread_id.inspect}"
      end
    end

    def __check_bindability
      return true if @bound_thread_id == :none || @bound_thread_id.nil?
      return true if @bound_thread_id == Thread.current.__id__
      raise BindingError,  "Object is bound to another thread and cannot be re- or un-bound"
    end

  end
end

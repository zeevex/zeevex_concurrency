require 'thread'
require 'countdownlatch'
require 'zeevex_concurrency'
require 'observer'

#
# base class for Promise, Future, etc. This should not be instantiated directly.
#
class ZeevexConcurrency::Delayed

  # @abstract Determine whether the Future is complete.
  #
  # @return [Boolean] true if the Future has completed or been cancelled
  def ready?; raise NotImplementedError; end


  #
  # @return [Exception, nil] the exception that failed this Delayed, if any
  #
  def exception
    @exception
  end

  #
  # Check to see whether the Delayed object failed with an exception.
  #
  # @return [Boolean] true if the Delayed failed during evaluation
  #
  def failed?
    !! @exception
  end

  #
  # Check to see whether the Delayed object was successful. Only
  # call on complete computations.
  #
  # @return [Boolean] true if the Delayed was successful
  # @raise ZeevexConcurrency::Delayed::IncompleteError if this computation has not completed
  #
  def successful?
    raise IncompleteError unless ready?
    @success
  end

  #
  # Check to see whether the Delayed object has already been evaluated.
  #
  # @return [Boolean] true if the Delayed was evaluated
  #
  def executed?
    @executed
  end

  #
  # Retrieve the value resulting from evaluation of the Delayed object.
  # If the Delayed has not completed yet, will block until it does.
  #
  # If the Delayed failed during evaluation, raises that exception.
  #
  # @param [Boolean] reraise if false, don't raise the exception from a failed
  #    evaluation. Just return the exception as a value.
  # @return [Object] the object resulting from the evaluation of the Delayed
  # @raise [StandardError] the exception
  #
  def value(reraise = true)
    result = _wait_for_value
    if @exception && reraise
      raise @exception
    elsif @exception
      @exception
    else
      result
    end
  end

  # Waits until the Delayed completed. If the Delayed has not completed yet,
  # will block until it does. If it has completed, returns immediately.
  #
  # If a timeout is supplied, will wait no longer tham `timeout` seconds.
  #
  # @param [Integer, nil] timeout if supplied and non-nil, the max seconds to wait
  # @return [Object] true on success, false on timeout
  #
  def wait(timeout = nil)
    Timeout::timeout(timeout) do
      value(false)
      true
    end
  rescue Timeout::Error
    false
  end

  protected

  def _initialize_delayed
    @mutex       = Mutex.new
    @exec_mutex  = Mutex.new
    @exception   = nil
    @result      = false
    @executed    = false
    @ready       = false
    @success     = false

    # from Cancellable
    @cancelled   = false

    # from Bindable
    @binding     = false
  end

  #
  # not MT-safe; only to be called from executor thread
  #
  def _execute(computation)
    raise "Already executed" if executed?
    raise ArgumentError, "Cannot execute without computation" unless computation
    @success = false
    begin
      result = computation.call
      @success = true
    rescue Exception
      @success = false
      @exception = $!
    end
    # run this separately so we can report exceptions in fulfill rather than capture them
    @mutex.synchronize do
      if @success
        fulfill(result)
      else
        smash(@exception)
      end
    end
    @executed = true
  rescue Exception
    puts "*** exception in fulfill: #{$!.inspect} #{$!.backtrace.join("\n")}***"
  ensure
    @executed = true
  end

  #
  # All Delayed classes should implement or call this method to deliver the
  # successful value or failure exception object to "consumers" of the Delayed
  #
  def fulfill(value, success = true)
    _fulfill(value, success)
  end

  #
  # not MT-safe; only to be called from executor thread
  #
  def smash(ex)
    @exception = ex
    fulfill ex, false
  end

  ###

  #
  # Raised when a fetch of the result value is attempted from a cancelled future.
  #
  class CancelledException < ::ZeevexConcurrency::ConcurrencyError; end

  #
  # Raised when a non-waiting method which requires a complete computation
  # is called on an incomplete computation
  #
  class IncompleteError < ::ZeevexConcurrency::ConcurrencyError; end
end

require 'zeevex_concurrency/delayed/convenience_methods'

module ZeevexConcurrency
  extend(ZeevexConcurrency::Delayed::ConvenienceMethods)
end

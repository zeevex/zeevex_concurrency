require 'timeout'
require 'observer'
require 'countdownlatch'
require 'zeevex_concurrency'
require 'zeevex_concurrency/delayed'

#
# A Multiplex is a wrapper around one or more deferred computations ({Future} or {Promise})
# which allows them to be waited upon as a group in various useful ways.
#
# Examples:
# - Blocking until all computations have completed
# - Returning the first complete computation
# - Waiting on and returning the first N complete computations
# - Returning a list the *results* of all {Delayed} objects (rather than the objects themselves)
# - Blocking waits from multiple "clients"
# - Combining one or more Future/Promise objects into a single Future
# - Transformation into an Oz-style Dataflow variable via a Future
#
# The {Delayed} object must implement Observable, and the Observable#notify_observer method
# must call its observer's #update method with the {Delayed} object as the first argument. e.g.
# the Promise, Future, or other such class should do this when it has completed:
#
#     changed
#     notify_observers(self)
#
# The {Delayed} object must also implement the #value method to retrieve the result of the
# computation
#
class ZeevexConcurrency::Multiplex
  include Observable

  #
  # Create a new Multiplex from a list of Futures, Promises, etc. upon which the
  # result of this Multiplex is dependent. The Multiplex is considered complete once
  # `count` of the included computations have completed *and* passed any supplied
  # filter.
  #
  # @param [Array] dependencies an array of computations to multiplex
  # @param [Integer, nil] count the number of computations which must complete and pass the filter
  #   for this Multiplex to be considered complete
  # @param [Hash] options a hash of options
  # @option options [Proc] :filter a proc which accepts a single argument and returns true or false
  #   if the supplied Delayed object is considered to have "passed" the filter. Only those Delayed
  #   objects which pass the filter are considered to be results and tallied against the `count`
  #   Note that the filter accepts the {Delayed} object itself, and not its result!
  # @option options [Array<#update>, #update] :observers an observer object or list of objects which
  #    have an #update method - this functions in the style of the standard Observable system.
  #
  # @see Multiplex.first_of
  # @see Multiplex.either
  # @see Multiplex.all
  # @see Multiplex.successes
  #
  def initialize(dependencies, count = nil, options = {})
    raise ArgumentError, "Must provide a list of dependencies" unless dependencies && !dependencies.empty?

    @count        = count
    @mutex        = Mutex.new
    @dependencies = dependencies.clone.freeze
    @waiting      = dependencies.clone
    @complete     = []
    @result       = []
    @filter       = options.delete(:filter)
    @failed       = false

    @latch        = CountDownLatch.new(count || @dependencies.length)

    Array(options.delete(:observer) || options.delete(:observers)).each do |observer|
      add_observer observer
    end

    @dependencies.each do |dep|
      dep.add_observer self
    end
  end

  #
  # Determine whether the Multiplex has completed.
  #
  # @return [Boolean] true if the Multiplex has completed
  def ready?
    @latch.count == 0
  end

  #
  # Waits until the Multiplex completes. If it has not completed yet,
  # will block until it does. If it has completed, returns immediately.
  #
  # If a timeout is supplied, will wait no longer tham `timeout` seconds.
  #
  # @param [Integer, nil] timeout if supplied and non-nil, the max seconds to wait
  # @return [Object] true on success, false on timeout
  #
  def wait(timeout = nil)
    @latch.wait(timeout)
  end

  #
  # Wait until this Multiplex has completed and return an array of the results.
  # Will also, by default, raise an IndexError if the Multiplex could not
  # complete.
  #
  # @return [Array] an array of the results
  # @raise IndexError if raise_if_failed==true and one or more of the included
  #   computations failed.
  #
  # @see #results
  #
  def value(raise_if_failed = true)
    wait
    if @failed && raise_if_failed
      raise IndexError, "Could not collect #{@count} result futures"
    else
      @result.dup
    end
  end

  #
  # Create a Future which can be used to receive the results of this Multiplex.
  #
  # @param [Boolean] raise_if_failed whether the resulting Future should be failed
  #   if any of the multiplexed futures fail
  # @return [Future] a future which will contain the results of this Multiplex
  #
  def as_future(raise_if_failed = true)
    ZeevexConcurrency.future { self.value(raise_if_failed) }
  end

  #
  # Provide access to the list of futures awaited by this Multiplex.
  #
  # @return [Array] the list of futures with which the Multiplex was created
  #
  def dependencies
    @dependencies
  end

  #
  # Fetch the current list of completed results. You may call this method before
  # all the Multiplexed objects have completed.
  #
  # @return [Array] an array of {Delayed} objects which have completed
  #
  def complete
    @complete.clone
  end

  #
  # Fetch the current list of completed and qualifying results. You may call this
  # method before all the Multiplexed objects have completed.
  #
  # The difference between this and {#complete} is that {#results} may be a subset
  # of {#complete}. The difference is basically this:
  #
  #    results = complete.select {|delayed| filter.call(delayed) }
  #
  # @return [Array] an array of {Delayed} objects which have completed and passed
  #   the filter.
  #
  def results
    @result.clone
  end

  #
  # Fetch the current list of uncompleted results. You may call this method before
  # all the Multiplexed objects have completed.
  #
  # @return [Array] an array of {Delayed} objects which have not yet completed
  #
  def waiting
    @waiting.clone
  end

  # callback from notifiers
  # @api private
  def update(source, *args)
    @mutex.synchronize do
      if @waiting.delete(source)
        @complete << source

        # does this one qualify?
        if !@done && (!@filter || @filter.call(source))
          @result << source
          do_complete if @latch.count == 1

          # release waiters
          @latch.countdown!
        end

        # we're out of candidates but don't have a complete result
        if @waiting.empty? && @latch.count > 0
          @failed = true
          do_complete
          @latch.count.times { @latch.countdown! }
        end
      else
        STDERR.puts "Received update from non-waiting source: #{source.inspect}"
      end
    end
  end

  # @private
  def add_observer_with_history(observer)
    @mutex.synchronize do
      add_observer_without_history observer
      if ready?
        do_notify_observers
      end
    end
  end

  alias_method :add_observer_without_history, :add_observer
  alias_method :add_observer, :add_observer_with_history

  protected

  def do_complete
    @done = true
    @result.freeze
    do_notify_observers
  end

  def do_notify_observers
    changed
    notify_observers self, @complete.clone
    delete_observers
  end

  public

  # Return a {Future} which contains the value of the first multiplexed computation
  # to complete. If the computation fails, then the returned Future will also be
  # failed with that exception.
  #
  # You may add observers and callbacks to the resulting future, wait on it,
  # retrieve its result, and even include it in other Multiplexes. It is in
  # every way a fully functional Future.
  #
  # @overload first_of(future1, future2, ..., options = {})
  #   Returns a Future containing the result of the first computation from the
  #   variable argument list to complete.
  #   @param [Future,Promise] future1 the first future to include
  #   @param [Future,Promise] future2 the second future to include
  #   @param [Future,Promise] ... the rest of the futures
  #   @param [Hash] options a hash of options which are accepted by {Future.create}
  #   @return [Future] the future which will contain the result
  #
  # @overload first_of(list_of_futures, options = {})
  #   Returns a Future containing the result of the first computation from
  #   list_of_futures to complete
  #   @param [Array] list_of_futures an array of Futures/Promises/etc. to multiplex
  #   @param [Hash] options a hash of options which are accepted by {Future.create}
  #   @return [Future] the future which will contain the result
  #
  # @see Future.create
  #
  def self.first_of(futures, *rest)
    futures = Array(futures) + rest
    options = futures.last.is_a?(Hash) ? futures.pop : {}
    # ZeevexConcurrency.future { new(futures, 1, options).value.first.value }
    new(futures, 1, options).as_future.flat_map {|list| list.first }
  end

  # Return a {Future} which contains the value of the first of two multiplexed
  # computations# to complete. If the first completed computation fails, then
  # the returned Future will also be failed with that exception.
  #
  # You may add observers and callbacks to the resulting future, wait on it,
  # retrieve its result, and even include it in other Multiplexes. It is in
  # every way a fully functional Future.
  #
  # @overload first_of(future1, future2, options = {})
  #   Returns a Future containing the result of the first computation from the
  #   variable argument list to complete.
  #   @param [Future,Promise] future1 the first future to include
  #   @param [Future,Promise] future2 the second future to include
  #   @param [Hash] options a hash of options which are accepted by {Future.create}
  #   @return [Future] the future which will contain the result
  #
  # @see Future.create
  #
  def self.either(future1, future2, options = {})
    first_of(future1, future2, options)
  end

  #
  # Return a list of all the values of all non-filtered futures after all futures have
  # finished. If there are any errors, this future will also contain that error instead
  # of the result list. The results will be ordered in the list to correspond to the
  # order of their Futures in the argument list. (i.e., preserves order)
  #
  # You may add observers and callbacks to the resulting future, wait on it,
  # retrieve its result, and even include it in other Multiplexes. It is in
  # every way a fully functional Future.
  #
  # @overload all(future1, future2, ..., options = {})
  #   Returns a Future containing the result of all the listedfutures.
  #
  #   @param [Future,Promise] future1 the first future to include
  #   @param [Future,Promise] future2 the second future to include
  #   @param [Future,Promise] ... the rest of the futures
  #   @param [Hash] options a hash of options which are accepted by {Future.create}
  #   @return [Future] the future which will contain the result
  #
  # @overload all(list_of_futures, options = {})
  #   Returns a Future containing the result of all the futures from
  #   list_of_futures.
  #
  #   @param [Array] list_of_futures an array of Futures/Promises/etc. to multiplex
  #   @param [Hash] options a hash of options which are accepted by {Future.create}
  #   @return [Future] the future which will contain the result
  #
  # @see Future.create
  #
  def self.all(futures, *rest)
    futures = Array(futures) + rest
    options = futures.last.is_a?(Hash) ? futures.pop : {}
    # ZeevexConcurrency.future { new(futures, futures.length, options).value.map &:value }
    new(futures, futures.length, options).as_future.map {|list| list.map &:value }
  end

  # Like {Multiplex.all}, returns a Future which waits for all futures to finish and contains a list
  # of their results in order. However, the result list will only contains values from
  # successful computations. Failures are excluded and will not cause this Future to fail.
  #
  # There may of course be fewer results than there were futures, and there is no way
  # currently to map results back to the futures which produced them.
  #
  # You may add observers and callbacks to the resulting future, wait on it,
  # retrieve its result, and even include it in other Multiplexes. It is in
  # every way a fully functional Future.
  #
  # @overload successes(future1, future2, ..., options = {})
  #   Returns a Future containing the result of all the listed futures which succeeded.
  #
  #   @param [Future,Promise] future1 the first future to include
  #   @param [Future,Promise] future2 the second future to include
  #   @param [Future,Promise] ... the rest of the futures
  #   @param [Hash] options a hash of options which are accepted by {Future.create}
  #   @return [Future] the future which will contain the result
  #
  # @overload all(list_of_futures, options = {})
  #   Returns a Future containing the result of all the futures from
  #   list_of_futures which succeeded.
  #
  #   @param [Array] list_of_futures an array of Futures/Promises/etc. to multiplex
  #   @param [Hash] options a hash of options which are accepted by {Future.create}
  #   @return [Future] the future which will contain the result
  #
  # @see Future.create
  # @see Multiplex.all
  #
  def self.successes(*futures)
    options = futures.last.is_a?(Hash) ? futures.pop : {}

    new(futures, futures.length, options).as_future(false).map do |flist|
      flist.flat_map do |f|
        [f.value] rescue []
      end
    end
  end
end


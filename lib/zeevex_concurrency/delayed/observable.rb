module ZeevexConcurrency::Delayed::Observable
  include ::Observable

  def self.included(base)
    base.class_eval do
      alias_method :add_observer_without_history, :add_observer
      alias_method :add_observer, :add_observer_with_history

      alias_method :fulfill_without_notification, :fulfill
      alias_method :fulfill, :fulfill_with_notification
    end
  end

  #
  # this ensures that an observer receives a value even after the value has
  # become available
  #
  # @private
  def add_observer_with_history(observer)
    @mutex.synchronize do
      if ready?
        # XXX: this is a bit hacky with both the functional and ivar access
        observer.send(:update, self, value(false), @success)
      else
        add_observer_without_history(observer)
      end
    end
  end

  # @private
  def fulfill_with_notification(result, success = true)
    fulfill_without_notification(result, success)
    _notify_and_remove_observers(result, success)
  end

  protected

  def _notify_and_remove_observers(result, success)
    changed
    begin
      notify_observers(self, result, success)
      delete_observers
    rescue Exception
      puts "Exception in notifying observers: #{$!.inspect} #{$!.backtrace.join("\n")}"
    end
  end
end

module ZeevexConcurrency::Delayed::Dataflowable
  def self.included(base)
    require 'zeevex_concurrency/deferred/dataflow'
  end

  #
  # Wraps a Delayed object with a transparent proxy to the result of the
  # Delayed object.  In other words, it will proxy messages from the Dataflow
  # object to whatever result a Future yields. It will block the first time
  # such a message is sent if the Future is not yet ready.
  #
  # If the Future yields an exception, any message sent to the Dataflow variable
  # will raise that exception.
  #
  # @return [Dataflow] a dataflow-style deferred value
  #
  def to_dataflow
    ZeevexConcurrency::Dataflow.new(self)
  end
end

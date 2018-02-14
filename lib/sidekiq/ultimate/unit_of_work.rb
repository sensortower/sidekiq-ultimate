# frozen_string_literal: true

require "sidekiq/throttled"

module Sidekiq
  module Ultimate
    # Job message envelope.
    #
    # @private
    class UnitOfWork
      # JSON payload
      #
      # @return [String]
      attr_reader :job

      # @param [QueueName] queue where job was pulled from
      # @param [String] job JSON payload
      def initialize(queue, job)
        @queue = queue
        @job   = job
      end

      # Pending jobs queue key name.
      #
      # @return [String]
      def queue
        @queue.pending
      end

      # Normalized `queue` name.
      #
      # @see QueueName#normalized
      # @return [String]
      def queue_name
        @queue.normalized
      end

      # Remove job from the inproc list.
      #
      # Sidekiq calls this when it thinks jobs was performed with no mistakes.
      #
      # @return [void]
      def acknowledge
        Sidekiq.redis { |redis| redis.lrem(@queue.inproc, -1, @job) }
      end

      # We gonna resurrect jobs that were inside inproc queue upon process
      # start, so no point in doing anything here.
      #
      # @return [void]
      def requeue
        # do nothing
      end

      # Pushes job back to the head of the queue, so that job won't be tried
      # immediately after it was requeued (in most cases).
      #
      # @note This is triggered when job is throttled. So it is same operation
      #   Sidekiq performs upon `Sidekiq::Worker.perform_async` call.
      #
      # @return [void]
      def requeue_throttled
        Sidekiq.redis do |redis|
          redis.pipeline do
            redis.lpush(@queue.pending, @job)
            acknowledge
          end
        end
      end

      # Tells whenever job should be pushed back to queue (throttled) or not.
      #
      # @see Sidekiq::Throttled.throttled?
      # @return [Boolean]
      def throttled?
        Sidekiq::Throttled.throttled?(@job)
      end
    end
  end
end

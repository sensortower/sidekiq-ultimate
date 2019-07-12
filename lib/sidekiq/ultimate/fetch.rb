# frozen_string_literal: true

require "sidekiq/throttled"

require "sidekiq/ultimate/expirable_set"
require "sidekiq/ultimate/queue_name"
require "sidekiq/ultimate/resurrector"
require "sidekiq/ultimate/unit_of_work"

module Sidekiq
  module Ultimate
    # Throttled reliable fetcher implementing reliable queue pattern.
    class Fetch
      # Delay between fetch retries in case of no job received.
      TIMEOUT = 2

      # Delay between queue poll attempts if last poll returned no jobs for it.
      QUEUE_TIMEOUT = 5

      # Delay between queue poll attempts if it's last job was throttled.
      THROTTLE_TIMEOUT = 15

      def initialize(options)
        @exhausted = ExpirableSet.new

        @debug  = ENV["DEBUG_SIDEKIQ_ULTIMATE"] ? {} : nil
        @strict = options[:strict] ? true : false
        @queues = options[:queues].map { |name| QueueName.new(name) }

        @queues.uniq! if @strict
      end

      # @return [UnitOfWork] if work can be processed
      def retrieve_work
        work = retrieve

        if work&.throttled?
          work.requeue_throttled

          @exhausted.add(work.queue, :ttl => THROTTLE_TIMEOUT)

          return nil
        end

        work
      end

      def self.bulk_requeue(units, _options)
        units.each(&:requeue)
      end

      def self.setup!
        Sidekiq.options[:fetch] = self
        Resurrector.setup!
      end

      private

      def retrieve
        Sidekiq.redis do |redis|
          queues.each do |queue|
            debug!(queue)

            job = redis.rpoplpush(queue.pending, queue.inproc)
            return UnitOfWork.new(queue, job) if job

            @exhausted.add(queue, :ttl => QUEUE_TIMEOUT)
          end
        end

        sleep TIMEOUT
        nil
      end

      def queues
        queues = (@strict ? @queues : @queues.shuffle.uniq) - @exhausted.to_a

        # Avoid calling heavier `paused_queue` if there's nothing to filter out
        return queues if queues.empty?

        queues - paused_queues
      end

      def paused_queues
        Sidekiq::Throttled::QueuesPauser.instance.
          instance_variable_get(:@paused_queues).
          map { |q| QueueName[q] }
      end

      def debug!(queue)
        return unless @debug

        previous, @debug[queue] = @debug[queue], Concurrent.monotonic_time

        return unless previous

        Sidekiq.logger.debug do
          "Queue #{queue} last time polled: #{@debug[queue] - previous} s ago"
        end
      end
    end
  end
end

# frozen_string_literal: true

require "sidekiq/throttled"

require "sidekiq/ultimate/expirable_set"
require "sidekiq/ultimate/queue_name"
require "sidekiq/ultimate/resurrector"
require "sidekiq/ultimate/unit_of_work"
require "sidekiq/ultimate/empty_queues"
require "sidekiq/ultimate/configuration"

module Sidekiq
  module Ultimate
    # Throttled reliable fetcher implementing reliable queue pattern.
    class Fetch
      # Delay between fetch retries in case of no job received.
      TIMEOUT = 2

      def initialize(options)
        @exhausted_by_throttling = ExpirableSet.new
        @empty_queues = Sidekiq::Ultimate::EmptyQueues.instance
        @strict = options[:strict] ? true : false
        @queues = options[:queues]

        @queues.uniq! if @strict

        @paused_queues            = []
        @paused_queues_expires_at = 0
      end

      # @return [UnitOfWork] if work can be processed
      def retrieve_work
        work = retrieve

        if work&.throttled?
          work.requeue_throttled

          @exhausted_by_throttling.add(
            work.queue_name, :ttl => Sidekiq::Ultimate::Configuration.instance.throttled_fetch_timeout_sec
          )

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
        EmptyQueues.setup!
      end

      private

      def retrieve
        Sidekiq.redis do |redis|
          queues_objects.each do |queue|
            job = redis.rpoplpush(queue.pending, queue.inproc)
            return UnitOfWork.new(queue, job) if job
          end
        end

        sleep TIMEOUT
        nil
      end

      def queues_objects
        queues = (@strict ? @queues : @queues.shuffle.uniq) - @exhausted_by_throttling.to_a - @empty_queues.queues

        # Avoid calling heavier `paused_queue` if there's nothing to filter out
        return [] if queues.empty?

        (queues - paused_queues).map { |name| QueueName.new(name) }
      end

      def paused_queues
        return @paused_queues if Time.now.to_i < @paused_queues_expires_at

        @paused_queues = Sidekiq::Throttled::QueuesPauser.instance.paused_queues
        @paused_queues_expires_at = Time.now.to_i + 60

        @paused_queues
      end
    end
  end
end

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
      # Timeout to sleep between fetch retries in case of no job received.
      TIMEOUT = 2

      # Timeout to sleep between queue fetch attempts in case if last job
      # of it was throttled.
      THROTTLE_TIMEOUT = 10

      def initialize(options)
        @exhausted = ExpirableSet.new

        @strict = options[:strict] ? true : false
        @queues = options[:queues].map { |name| QueueName.new(name) }

        @queues.uniq! if @strict
      end

      def retrieve_work
        work = retrieve

        return unless work
        return work unless work.throttled?

        work.requeue_throttled

        @exhausted.add(work.queue, :ttl => THROTTLE_TIMEOUT)
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
            job = redis.rpoplpush(queue.pending, queue.inproc)
            return UnitOfWork.new(queue, job) if job

            @exhausted.add(queue, :ttl => TIMEOUT)
          end
        end

        sleep TIMEOUT
        nil
      end

      def queues
        (@strict ? @queues : @queues.shuffle.uniq) - exhausted - paused_queues
      end

      def exhausted
        @exhausted.to_a
      end

      def paused_queues
        Sidekiq::Throttled::QueuesPauser.instance.
          instance_variable_get(:@paused_queues).
          map { |q| QueueName[q] }
      end
    end
  end
end

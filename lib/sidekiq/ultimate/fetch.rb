# frozen_string_literal: true

require "sidekiq/throttled"

require "sidekiq/ultimate/debugging"
require "sidekiq/ultimate/expirable_set"
require "sidekiq/ultimate/queue_name"
require "sidekiq/ultimate/resurrector"
require "sidekiq/ultimate/unit_of_work"

module Sidekiq
  module Ultimate
    # Throttled reliable fetcher implementing reliable queue pattern.
    class Fetch
      include Debugging

      # Timeout to sleep between fetch retries in case of no job received.
      TIMEOUT = 2

      QUEUE_TIMEOUT = 5

      # Timeout to sleep between queue fetch attempts in case if last job
      # of it was throttled.
      THROTTLE_TIMEOUT = 15

      def initialize(options)
        @exhausted = ExpirableSet.new

        @strict = options[:strict] ? true : false
        @queues = options[:queues].map { |name| QueueName.new(name) }

        @queues.uniq! if @strict
      end

      def retrieve_work
        work = retrieve

        if work&.throttled?
          work.requeue_throttled

          debug! { "Queue #{queue} got throttled job." }
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
            job = redis.rpoplpush(queue.pending, queue.inproc)
            return UnitOfWork.new(queue, job) if job

            debug! { "Queue #{queue} has no job." }
            @exhausted.add(queue, :ttl => QUEUE_TIMEOUT)
          end
        end

        debug! { "No jobs in any queues." }

        sleep TIMEOUT
        nil
      end

      def queues
        queues  = @strict ? @queues : @queues.shuffle.uniq
        queues -= @exhausted_queues.to_a
        queues -= paused_queues unless queues.empty?

        debug! { "Queues to poll: #{queues.map(&:to_s).join(', ')}" }

        queues
      end

      def paused_queues
        Sidekiq::Throttled::QueuesPauser.instance.
          instance_variable_get(:@paused_queues).
          map { |q| QueueName[q] }
      end
    end
  end
end

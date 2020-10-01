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

        @strict = options[:strict] ? true : false
        @queues = options[:queues].map { |name| QueueName.new(name) }

        @queues.uniq! if @strict

        @paused_queues            = []
        @paused_queues_expires_at = 0
      end

      # @return [UnitOfWork] if work can be processed
      def retrieve_work
        work = retrieve

        if work&.throttled?
          work.requeue_throttled

          queue = QueueName.new(work.queue_name)
          @exhausted.add(queue, :ttl => THROTTLE_TIMEOUT)

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
        return @paused_queues if Time.now.to_i < @paused_queues_expires_at

        @paused_queues = Sidekiq::Throttled::QueuesPauser.instance.paused_queues.map { |q| QueueName[q] }.freeze
        @paused_queues_expires_at = Time.now.to_i + 60

        @paused_queues
      end
    end
  end
end

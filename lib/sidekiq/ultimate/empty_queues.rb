# frozen_string_literal: true

require "redlock"
require "singleton"

require "sidekiq/ultimate/configuration"
require "sidekiq/ultimate/empty_queues/refresh_timer_task"

module Sidekiq
  module Ultimate
    # Maintains a cache of empty queues. It has a global cache and a local cache.
    # The global cache is stored in redis and updated periodically. The local cache is updated either by using the fresh
    # cache fetched after global cache update or by using existing global cache.
    # Only one process can update the global cache at a time.
    class EmptyQueues
      include Singleton

      LOCK_KEY = "ultimate:empty_queues_updater:lock"
      LAST_RUN_KEY = "ultimate:empty_queues_updater:last_run"
      KEY = "ultimate:empty_queues"

      attr_reader :queues, :local_lock

      def initialize
        @local_lock = Mutex.new
        @queues = []

        super
      end

      # Sets up automatic empty queues cache updater.
      # It will call #refresh! every
      # `Sidekiq::Ultimate::Configuration.instance.empty_queues_cache_refresh_interval_sec` seconds
      def self.setup!
        refresher_timer_task = nil

        Sidekiq.on(:startup) do
          refresher_timer_task&.shutdown
          refresher_timer_task = RefreshTimerTask.setup!(self)
        end

        Sidekiq.on(:shutdown) { refresher_timer_task&.shutdown }
      end

      # Attempts to update the global cache of empty queues by first acquiring a global lock
      # If the lock is acquired, it brute force generates an accurate list of currently empty queues and
      # then writes the updated list to the global cache
      # The local queue cache is always updated as a result of this operation, either by using the recently generated
      # list or fetching the most recent list from the global cache
      #
      # @return [Boolean] true if local cache was updated
      def refresh!
        return false unless local_lock.try_lock

        begin
          refresh_global_cache! || refresh_local_cache
        ensure
          local_lock.unlock
        end
      rescue => e
        Sidekiq.logger.error { "Empty queues cache update failed: #{e}" }
        raise
      end

      private

      # Automatically updates local cache if global cache was updated
      # @return [Boolean] true if cache was updated
      def refresh_global_cache!
        Sidekiq.logger.debug { "Refreshing global cache" }

        global_lock do
          Sidekiq.redis do |redis|
            empty_queues = generate_empty_queues(redis)

            update_global_cache(redis, empty_queues)
            update_local_cache(empty_queues)
          end
        end
      end

      def generate_empty_queues(redis)
        # Cursor is not atomic, so there may be duplicates because of concurrent update operations
        queues = Sidekiq.redis { |r| r.sscan_each("queues").to_a.uniq }

        queues_statuses =
          redis.pipelined do |p|
            queues.each do |queue|
              p.exists?(QueueName.new(queue).pending)
            end
          end

        queues.zip(queues_statuses).reject { |(_, exists)| exists }.map(&:first)
      end

      def refresh_local_cache
        Sidekiq.logger.debug { "Refreshing local cache" }

        # Cursor is not atomic, so there may be duplicates because of concurrent update operations
        list = Sidekiq.redis { |redis| redis.sscan_each(KEY).to_a.uniq }
        update_local_cache(list)
      end

      def update_global_cache(redis, list)
        Sidekiq.logger.debug { "Setting global cache: #{list}" }

        redis.multi do |multi|
          multi.del(KEY)
          multi.sadd(KEY, list) if list.any?
        end
      end

      def update_local_cache(list)
        Sidekiq.logger.debug { "Setting local cache: #{list}" }

        @queues = list
      end

      # @return [Boolean] true if lock was acquired
      def global_lock
        Sidekiq.redis do |redis|
          break false if skip_update?(redis) # Cheap check since lock will not be free most of the time

          Redlock::Client.new([redis], :retry_count => 0).lock(LOCK_KEY, 30_000) do |locked|
            break false unless locked
            break false if skip_update?(redis)

            yield

            redis.set(LAST_RUN_KEY, redis.time.first)
          end
        end
      end

      def skip_update?(redis)
        results = redis.pipelined { |pipeline| [pipeline.time, pipeline.get(LAST_RUN_KEY)] }
        last_run_distance = results[0][0] - results[1].to_i

        last_run_distance < Sidekiq::Ultimate::Configuration.instance.empty_queues_cache_refresh_interval_sec
      end
    end
  end
end

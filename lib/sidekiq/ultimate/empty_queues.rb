# frozen_string_literal: true

require "redlock"
require "singleton"

require "sidekiq/ultimate/configuration"
require "sidekiq/ultimate/use_exists_question_mark"
require "sidekiq/ultimate/redis_sscan"
require "sidekiq/ultimate/empty_queues/refresh_timer_task"

module Sidekiq
  module Ultimate
    # Maintains a list of empty queues. It has a global list and a local list.
    # The global list is stored in redis and updated periodically. The local list is updated either by using the fresh
    # list fetched for global list update or by using existing global list.
    # Only one process can update the global list at a time.
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

      # Sets up automatic empty queues list updater.
      # It will call #refresh! every
      # `Sidekiq::Ultimate::Configuration.instance.empty_queues_refresh_interval_sec` seconds
      def self.setup!
        refresher = nil

        Sidekiq.on(:startup) do
          refresher&.shutdown
          refresher = RefreshTimerTask.setup!(self)
        end

        Sidekiq.on(:shutdown) { refresher&.shutdown }
      end

      # It updates the global list of empty queues and the local list of empty queues.
      # During the update, the global list is locked to prevent other processes from updating it since this operation
      # is expensive.
      # The local list is updated anyway. Either by using the fresh list fetched for global list update or by using
      # existing global list.
      #
      # @return [Boolean] true if local list was updated
      def refresh!
        return false unless local_lock.try_lock

        begin
          refresh_global_list! || refresh_local_list!
        ensure
          local_lock.unlock
        end
      rescue => e
        Sidekiq.logger.error { "Empty queues list update failed: #{e}" }
        raise
      end

      private

      # Automatically updates local list if global list was updated
      # @return [Boolean] true if list was updated
      def refresh_global_list!
        Sidekiq.logger.debug { "Refreshing global list" }

        global_lock do
          Sidekiq.redis do |redis|
            empty_queues = fetch_empty_queues(redis)

            set_global_list!(redis, empty_queues)
            set_local_list!(empty_queues)
          end
        end
      end

      def fetch_empty_queues(redis)
        queues = Sidekiq::Ultimate::RedisSscan.read(redis, "queues")

        queues_statuses =
          redis.pipelined do |p|
            queues.each do |queue|
              pending_queue = QueueName.new(queue).pending

              Sidekiq::Ultimate::UseExistsQuestionMark.use? ? p.exists?(pending_queue) : p.exists(pending_queue)
            end
          end

        queues.zip(queues_statuses).reject { |(_, exists)| exists }.map(&:first)
      end

      def refresh_local_list!
        Sidekiq.logger.debug { "Refreshing local list" }

        list = Sidekiq.redis { |redis| Sidekiq::Ultimate::RedisSscan.read(redis, KEY) }
        set_local_list!(list)
      end

      def set_global_list!(redis, list)
        Sidekiq.logger.debug { "Setting global list: #{list}" }

        redis.multi do |multi|
          multi.del(KEY)
          multi.sadd(KEY, list) if list.any?
        end
      end

      def set_local_list!(list) # rubocop:disable Naming/AccessorMethodName
        Sidekiq.logger.debug { "Setting local list: #{list}" }

        @queues = list
      end

      # @return [Boolean] true if lock was acquired
      def global_lock
        Sidekiq.redis do |redis|
          break false if skip_update?(redis) # Cheap check since lock will not be free most of the time

          Redlock::Client.new([redis], :retry_count => 0).lock(namespaced_lock_key, 30_000) do |locked|
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

        last_run_distance < Sidekiq::Ultimate::Configuration.instance.empty_queues_refresh_interval_sec
      end

      def namespaced_lock_key
        return @namespaced_lock_key if defined?(@namespaced_lock_key)

        namespace = Sidekiq.redis { |redis| redis.namespace if redis.respond_to?(:namespace) }
        @namespaced_lock_key = "#{namespace}:#{LOCK_KEY}"
      end
    end
  end
end

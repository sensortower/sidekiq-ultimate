# frozen_string_literal: true

require "concurrent/timer_task"
require "redlock"
require "singleton"

require "sidekiq/ultimate/configuration"
require "sidekiq/ultimate/use_exists_question_mark"

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
      # It will call #refresh! every `Sidekiq::Ultimate::Configuration.instance.empty_queues_refresh_interval` seconds.
      def self.setup!
        refresher = nil

        Sidekiq.on(:startup) do
          refresher&.shutdown

          refresher = Concurrent::TimerTask.execute({
            :run_now            => true,
            :execution_interval => Sidekiq::Ultimate::Configuration.instance.empty_queues_refresh_interval
          }) { Sidekiq::Ultimate::EmptyQueues.instance.refresh! }
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
      end

      private

      # Automatically updates local list if global list was updated
      # @return [Boolean] true if list was updated
      def refresh_global_list!
        global_lock do
          Sidekiq.redis do |redis|
            empty_queues = fetch_empty_queues(redis)

            set_global_list!(redis, empty_queues)
            set_local_list!(empty_queues)
          end
        end
      end

      def fetch_empty_queues(redis)
        queues = sscan(redis, "queues")

        queues_statuses =
          redis.pipelined do |pipeline|
            queues.each do |queue|
              Sidekiq::Ultimate::UseExistsQuestionMark.use? ? pipeline.exists?(queue) : pipeline.exists(queue)
            end
          end

        queues.zip(queues_statuses).reject { |(_, exists)| exists }.map(&:first)
      end

      def refresh_local_list!
        @queues = Sidekiq.redis { |redis| redis.smembers(KEY) }
      end

      def set_global_list!(redis, list)
        redis.multi do |multi|
          multi.del(KEY)
          multi.sadd(KEY, list)
        end
      end

      def set_local_list!(list) # rubocop:disable Naming/AccessorMethodName
        @queues = list
      end

      # @return [Boolean] true if lock was acquired
      def global_lock
        return false if Sidekiq.redis { |r| skip_update?(r) }

        Sidekiq.redis do |redis|
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

        last_run_distance < Sidekiq::Ultimate::Configuration.instance.empty_queues_refresh_interval
      end

      def sscan(conn, key)
        cursor = "0"
        result = []
        loop do
          cursor, values = conn.sscan(key, cursor)
          result.push(*values)
          break if cursor == "0"
        end
        result
      end
    end
  end
end

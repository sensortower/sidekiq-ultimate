# frozen_string_literal: true

require "singleton"

module Sidekiq
  module Ultimate
    # Configuration options.
    class Configuration
      include Singleton

      # @return [Proc] callback to be called when job is resurrected
      # @yieldparam queue_name [String] name of the queue
      # @yieldparam jobs_count [Integer] number of jobs resurrected
      # @yieldreturn [void]
      # @example
      #  Sidekiq::Ultimate::Configuration.instance.on_resurrection = ->(queue_name, jobs_count) do
      #    puts "Resurrected #{jobs_count} jobs from #{queue_name}"
      #  end
      attr_accessor :on_resurrection

      # resurrection counter can be enabled to count how many times a job was resurrected.
      # If `enable_resurrection_counter` setting is enabled, on each resurrection event, a counter is increased.
      # Counter value is stored in redis by jid and has expiration time 24 hours.
      # @return [Boolean]
      attr_accessor :enable_resurrection_counter

      # It specifies how often the list of empty queues should be refreshed.
      # In a nutshell, it specifies the maximum possible delay between a job was pushed to previously empty queue and
      # the moment when that new job is picked up.
      # Note that every worker needs to maintain its own local list of empty queues. Setting this interval to a low
      # values will increase the number of redis calls and will increase the load on redis.
      # @return [Integer] interval in seconds to refresh the list of empty queues
      attr_reader :empty_queues_refresh_interval_sec

      DEFAULT_EMPTY_QUEUES_REFRESH_INTERVAL_SEC = 30

      def initialize
        @empty_queues_refresh_interval_sec = DEFAULT_EMPTY_QUEUES_REFRESH_INTERVAL_SEC
        super
      end

      def empty_queues_refresh_interval_sec=(value)
        unless value.is_a?(Numeric)
          raise ArgumentError, "Invalid 'empty_queues_refresh_interval_sec' value: #{value}. Must be Numeric"
        end

        @empty_queues_refresh_interval_sec = value
      end
    end
  end
end

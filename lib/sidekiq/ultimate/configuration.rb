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
      attr_accessor :enable_resurrection_counter

      attr_reader :empty_queues_refresh_interval

      DEFAULT_EMPTY_QUEUES_REFRESH_INTERVAL = 30

      def initialize
        @empty_queues_refresh_interval = DEFAULT_EMPTY_QUEUES_REFRESH_INTERVAL
        super
      end

      def empty_queues_refresh_interval=(value)
        unless value.is_a?(Numeric)
          raise ArgumentError, "Invalid 'empty_queues_refresh_interval' value: #{value}. Must be Numeric"
        end

        @empty_queues_refresh_interval = value.to_i
      end
    end
  end
end

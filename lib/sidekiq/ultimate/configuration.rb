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
    end
  end
end

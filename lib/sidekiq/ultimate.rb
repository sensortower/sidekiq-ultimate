# frozen_string_literal: true

require "sidekiq/throttled"

require "sidekiq/ultimate/configuration"

module Sidekiq
  # Sidekiq ultimate experience.
  module Ultimate
    class << self
      # Sets up reliable throttled fetch and friends.
      # @return [void]
      def setup!(&configuration_block)
        configuration_block&.call(Sidekiq::Ultimate::Configuration.instance)

        Sidekiq::Throttled::Communicator.instance.setup!
        Sidekiq::Throttled::QueuesPauser.instance.setup!

        sidekiq_configure_server
      end

      private

      def sidekiq_configure_server
        Sidekiq.configure_server do |config|
          require "sidekiq/ultimate/fetch"
          Sidekiq::Ultimate::Fetch.setup!

          require "sidekiq/throttled/middleware"
          config.server_middleware do |chain|
            chain.add Sidekiq::Throttled::Middleware
          end
        end
      end
    end
  end
end

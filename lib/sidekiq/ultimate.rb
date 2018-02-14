# frozen_string_literal: true

require "sidekiq/throttled"

require "sidekiq/ultimate/version"

module Sidekiq
  # Sidekiq ultimate experience.
  module Ultimate
    class << self
      # Sets up reliable throttled fetch and friends.
      # @return [void]
      def setup!
        Sidekiq::Throttled::Communicator.instance.setup!
        Sidekiq::Throttled::QueuesPauser.instance.setup!

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

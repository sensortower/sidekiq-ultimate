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
      class Debug
        def initialize
          @queues_stats = {}
        end
      end
    end
  end
end

# frozen_string_literal: true

require "redlock"
require "sidekiq/ultimate/resurrector/common_constants"

module Sidekiq
  module Ultimate
    module Resurrector
      # Ensures exclusive access to resurrection process
      class Lock
        LOCK_KEY = "#{CommonConstants::MAIN_KEY}:lock"
        private_constant :LOCK_KEY

        LAST_RUN_KEY = "#{CommonConstants::MAIN_KEY}:last_run"
        private_constant :LAST_RUN_KEY

        LOCK_TTL = 30_000 # ms
        private_constant :LOCK_TTL

        class << self
          def acquire
            Sidekiq.redis do |redis|
              Redlock::Client.new([redis], :retry_count => 0).lock(LOCK_KEY, LOCK_TTL) do |locked|
                break unless locked

                results  = redis.pipelined { |pipeline| [pipeline.time, pipeline.get(LAST_RUN_KEY)] }
                distance = results[0][0] - results[1].to_i

                break unless CommonConstants::RESURRECTOR_INTERVAL < distance

                yield

                redis.set(LAST_RUN_KEY, redis.time.first)
              end
            end
          end
        end
      end
    end
  end
end

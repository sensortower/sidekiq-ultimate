# frozen_string_literal: true

require "redis/lockers"
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

        LOCK_TTL = 30_000
        private_constant :LOCK_TTL

        class << self
          def acquire
            Sidekiq.redis do |redis|
              Redis::Lockers.acquire(redis, LOCK_KEY, :ttl => LOCK_TTL) do
                results  = redis.pipelined { |r| [r.time, r.get(LAST_RUN_KEY)] }
                distance = results[0][0] - results[1].to_i

                break unless 60 < distance

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

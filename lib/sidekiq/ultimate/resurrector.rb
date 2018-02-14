# frozen_string_literal: true

require "redis/lockers"
require "redis/prescription"

module Sidekiq
  module Ultimate
    # Lost jobs resurrector.
    module Resurrector
      LPOPRPUSH = Redis::Prescription.read("#{__dir__}/lpoprpush.lua")
      private_constant :LPOPRPUSH

      MAIN_KEY = "ultimate:resurrector"
      private_constant :MAIN_KEY

      LOCK_KEY = "#{MAIN_KEY}:lock"
      private_constant :LOCK_KEY

      class << self
        def setup!
          ctulhu = Concurrent::TimerTask.new(:execution_interval => 5) do
            resurrect!
          end

          Sidekiq.on(:startup) do
            register_process!
            ctulhu.execute
          end

          Sidekiq.on(:shutdown) { ctulhu.shutdown }
        end

        def resurrect!
          lock do
            casualties.each do |identity|
              queues(identity).each { |queue| resurrect(queue) }
              cleanup(identity)
            end
          end
        end

        private

        def register_process!
          Sidekiq.redis do |redis|
            queues   = JSON.dump(Sidekiq.options[:queues].uniq)
            identity = Object.new.tap { |o| o.extend Sidekiq::Util }.identity

            redis.hset(MAIN_KEY, identity, queues)
          end
        end

        def lock(&block)
          Sidekiq.redis do |redis|
            Redis::Lockers.acquire(redis, LOCK_KEY, :ttl => 30_000, &block)
          end
        end

        def casualties
          Sidekiq.redis do |redis|
            casualties = []
            identities = redis.hkeys(MAIN_KEY)

            redis.pipelined { identities.each { |k| redis.exists k } }.
              each_with_index { |v, i| casualties << identities[i] unless v }

            casualties
          end
        end

        def queues(identity)
          Sidekiq.redis do |redis|
            queues = redis.hget(MAIN_KEY, identity)

            return [] unless queues

            JSON.parse(queues).map do |q|
              QueueName.new(q, :identity => identity)
            end
          end
        end

        def resurrect(queue)
          Sidekiq.redis do |redis|
            kwargs = { :keys => [queue.inproc, queue.pending] }
            count  = 0

            count += 1 while LPOPRPUSH.eval(redis, **kwargs)
            redis.del(queue.inproc)
          end
        end

        def cleanup(identity)
          Sidekiq.redis { |redis| redis.hdel(MAIN_KEY, identity) }
        end
      end
    end
  end
end

# frozen_string_literal: true

require "redis/lockers"
require "redis/prescription"

require "sidekiq/ultimate/queue_name"

module Sidekiq
  module Ultimate
    # Lost jobs resurrector.
    module Resurrector
      RESURRECT = Redis::Prescription.read \
        "#{__dir__}/resurrector/resurrect.lua"
      private_constant :RESURRECT

      SAFECLEAN = Redis::Prescription.read \
        "#{__dir__}/resurrector/safeclean.lua"
      private_constant :SAFECLEAN

      MAIN_KEY = "ultimate:resurrector"
      private_constant :MAIN_KEY

      LOCK_KEY = "#{MAIN_KEY}:lock"
      private_constant :LOCK_KEY

      class << self
        # rubocop: disable Metrics/MethodLength
        def setup!
          ctulhu    = nil
          monitor   = nil

          @identity = Object.new.tap { |o| o.extend Sidekiq::Util }.identity

          Sidekiq.on(:startup) do
            options = { :run_now => true, :execution_interval => 60 }
            ctulhu  = Concurrent::TimerTask.execute(options) { resurrect! }
          end

          Sidekiq.on(:heartbeat) do
            options = { :run_now => true, :execution_interval => 5 }
            monitor = Concurrent::TimerTask.execute(options) { defibrillate! }
          end

          Sidekiq.on(:shutdown) do
            monitor&.shutdown
            ctulhu&.shutdown
          end
        end
        # rubocop: enable Metrics/MethodLength

        def resurrect!
          lock do
            casualties.each do |identity|
              log(:debug) { "Resurrecting #{identity}" }

              queues = queues_of(identity).each { |queue| resurrect(queue) }
              cleanup(identity, queues.map(&:inproc))
            end
          end
        rescue => e
          log(:error) { "Resurrection failed: #{e}" }
          raise
        end

        private

        def defibrillate!
          Sidekiq.redis do |redis|
            log(:debug) { "Defibrillating" }

            queues = JSON.dump(Sidekiq.options[:queues].uniq)
            redis.hset(MAIN_KEY, @identity, queues)
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

        def queues_of(identity)
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
            result = RESURRECT.eval(redis, {
              :keys => [queue.inproc, queue.pending]
            })

            if result.positive?
              log(:info) { "Resurrected #{result} jobs from #{queue.inproc}" }
            end
          end
        end

        def cleanup(identity, inprocs)
          Sidekiq.redis do |redis|
            result = SAFECLEAN.eval(redis, {
              :keys => [MAIN_KEY, *inprocs],
              :argv => [identity]
            })

            log(:debug) { "Safeclean of #{identity} ok=#{1 == result}" }
          end
        end

        def log(level)
          Sidekiq.logger.public_send(level) do
            "[#{self}] @#{@identity} #{yield}"
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

require "redis/prescription"
require "concurrent/timer_task"

require "sidekiq/ultimate/queue_name"
require "sidekiq/ultimate/resurrector/lock"
require "sidekiq/ultimate/resurrector/common_constants"
require "sidekiq/ultimate/configuration"

module Sidekiq
  module Ultimate
    # Lost jobs checker and resurrector
    module Resurrector
      RESURRECT = Redis::Prescription.read("#{__dir__}/resurrector/resurrect.lua")
      private_constant :RESURRECT

      SAFECLEAN = Redis::Prescription.read("#{__dir__}/resurrector/safeclean.lua")
      private_constant :SAFECLEAN

      DEFIBRILLATE_INTERVAL = 5
      private_constant :DEFIBRILLATE_INTERVAL

      class << self
        def setup!
          register_aed!
          call_cthulhu!
        end

        # go over all sidekiq processes (identities) that were shut down recently, get all their queues and
        # try to resurrect them
        def resurrect!
          Sidekiq::Ultimate::Resurrector::Lock.acquire do
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

        def current_process_identity
          @current_process_identity ||= Object.new.tap { |o| o.extend Sidekiq::Util }.identity
        end

        private

        def call_cthulhu!
          cthulhu = nil

          Sidekiq.on(:startup) do
            cthulhu&.shutdown

            cthulhu = Concurrent::TimerTask.execute({
              :run_now            => true,
              :execution_interval => CommonConstants::RESURRECTOR_INTERVAL
            }) { resurrect! }
          end

          Sidekiq.on(:shutdown) { cthulhu&.shutdown }
        end

        def register_aed!
          aed = nil

          Sidekiq.on(:heartbeat) do
            aed&.shutdown

            aed = Concurrent::TimerTask.execute({
              :run_now            => true,
              :execution_interval => DEFIBRILLATE_INTERVAL
            }) { defibrillate! }
          end

          Sidekiq.on(:shutdown) { aed&.shutdown }
        end

        # put current list of queues into resurrection candidates
        def defibrillate!
          Sidekiq.redis do |redis|
            log(:debug) { "Defibrillating" }

            queues = JSON.dump(Sidekiq.options[:queues].uniq)
            redis.hset(CommonConstants::MAIN_KEY, current_process_identity, queues)
          end
        end

        # list of processes that disappeared after latest #defibrillate!
        def casualties
          Sidekiq.redis do |redis|
            casualties = []
            identities = redis.hkeys(CommonConstants::MAIN_KEY)

            redis.pipelined { identities.each { |k| redis.exists? k } }.
              each_with_index { |v, i| casualties << identities[i] unless v }

            casualties
          end
        end

        # Get list of genuine sidekiq queues names for a given identity (sidekiq process id)
        def queues_of(identity)
          Sidekiq.redis do |redis|
            queues = redis.hget(CommonConstants::MAIN_KEY, identity)

            return [] unless queues

            JSON.parse(queues).map do |q|
              QueueName.new(q, :identity => identity)
            end
          end
        end

        # Move jobs from inproc to pending
        def resurrect(queue)
          Sidekiq.redis do |redis|
            result = RESURRECT.eval(redis, {
              :keys => [queue.inproc, queue.pending]
            })

            if result.positive?
              log(:info) { "Resurrected #{result} jobs from #{queue.inproc}" }
              Sidekiq::Ultimate::Configuration.instance.on_resurrection&.call(queue.to_s, result.to_i)
            end
          end
        end

        # Delete empty inproc queues and clean up identity key from resurrection candidates (CommonConstants::MAIN_KEY)
        def cleanup(identity, inprocs)
          Sidekiq.redis do |redis|
            result = SAFECLEAN.eval(redis, {
              :keys => [CommonConstants::MAIN_KEY, *inprocs],
              :argv => [identity]
            })

            log(:debug) { "Safeclean of #{identity} ok=#{1 == result}" }
          end
        end

        def log(level)
          Sidekiq.logger.public_send(level) do
            "[#{self}] @#{current_process_identity} #{yield}"
          end
        end
      end
    end
  end
end

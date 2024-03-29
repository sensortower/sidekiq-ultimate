# frozen_string_literal: true

require "redis_prescription"
require "concurrent/timer_task"

require "sidekiq/component"
require "sidekiq/ultimate/queue_name"
require "sidekiq/ultimate/resurrector/lock"
require "sidekiq/ultimate/resurrector/common_constants"
require "sidekiq/ultimate/resurrector/resurrection_script"
require "sidekiq/ultimate/configuration"
require "sidekiq/ultimate/interval_with_jitter"

module Sidekiq
  module Ultimate
    # Lost jobs checker and resurrector
    module Resurrector
      SAFECLEAN = RedisPrescription.new(File.read("#{__dir__}/resurrector/lua_scripts/safeclean.lua"))
      private_constant :SAFECLEAN

      DEFIBRILLATE_INTERVAL = 5
      private_constant :DEFIBRILLATE_INTERVAL

      ResurrectorTimerTask = Class.new(Concurrent::TimerTask)
      HeartbeatTimerTask = Class.new(Concurrent::TimerTask)

      class << self
        def setup!
          register_process_heartbeat
          register_resurrector
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
          @current_process_identity ||= Object.new.tap { |o| o.extend Sidekiq::Component }.identity
        end

        private

        def register_resurrector
          resurrector_timer_task = nil

          Sidekiq.on(:startup) do
            resurrector_timer_task&.shutdown

            resurrector_timer_task = ResurrectorTimerTask.new({
              :run_now            => true,
              :execution_interval => Sidekiq::Ultimate::IntervalWithJitter.call(CommonConstants::RESURRECTOR_INTERVAL)
            }) { resurrect! }
            resurrector_timer_task.execute
          end

          Sidekiq.on(:shutdown) { resurrector_timer_task&.shutdown }
        end

        def register_process_heartbeat
          heartbeat_timer_task = nil

          Sidekiq.on(:heartbeat) do
            heartbeat_timer_task&.shutdown

            heartbeat_timer_task = HeartbeatTimerTask.new({
              :run_now            => true,
              :execution_interval => Sidekiq::Ultimate::IntervalWithJitter.call(DEFIBRILLATE_INTERVAL)
            }) { save_watched_queues }
            heartbeat_timer_task.execute
          end

          Sidekiq.on(:shutdown) { heartbeat_timer_task&.shutdown }
        end

        # put current list of queues into resurrection candidates
        def save_watched_queues
          Sidekiq.redis do |redis|
            log(:debug) { "Defibrillating" }

            queues = JSON.dump(Sidekiq[:queues].uniq)
            redis.hset(CommonConstants::MAIN_KEY, current_process_identity, queues)
          end
        end

        # list of processes that disappeared after latest #save_watched_queues
        def casualties
          Sidekiq.redis do |redis|
            sidekiq_processes = redis.hkeys(CommonConstants::MAIN_KEY)

            sidekiq_processes_alive = redis.pipelined do |pipeline|
              sidekiq_processes.each do |process|
                pipeline.exists?(process)
              end
            end

            sidekiq_processes.zip(sidekiq_processes_alive).reject { |(_, alive)| alive }.map(&:first)
          end
        end

        # Get list of genuine sidekiq queues names for a given identity (sidekiq process id)
        def queues_of(identity)
          Sidekiq.redis do |redis|
            queues = redis.hget(CommonConstants::MAIN_KEY, identity)

            return [] unless queues

            JSON.parse(queues).map { |q| QueueName.new(q, :identity => identity) }
          end
        end

        # Move jobs from inproc to pending
        def resurrect(queue)
          Sidekiq.redis do |redis|
            resurrected_jobs_count = ResurrectionScript.call(redis, :keys => [queue.inproc, queue.pending])

            if resurrected_jobs_count.positive?
              log(:info) { "Resurrected #{resurrected_jobs_count} jobs from #{queue.inproc}" }
              Sidekiq::Ultimate::Configuration.instance.on_resurrection&.call(queue.to_s, resurrected_jobs_count)
            end
          end
        end

        # Delete empty inproc queues and clean up identity key from resurrection candidates (CommonConstants::MAIN_KEY)
        def cleanup(identity, inprocs)
          Sidekiq.redis do |redis|
            result = SAFECLEAN.call(redis, :keys => [CommonConstants::MAIN_KEY, *inprocs], :argv => [identity])
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

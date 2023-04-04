# frozen_string_literal: true

require "sidekiq/ultimate/resurrector"

RSpec.describe Sidekiq::Ultimate::Resurrector do
  let(:identity) { "hostname:pid:123456" }
  let(:sidekiq_util) { Object.new.tap { |o| o.extend Sidekiq::Util } }

  before do
    allow(described_class).to receive(:current_process_identity).and_return(identity)
  end

  describe ".resurrect!" do
    subject(:resurrect!) { described_class.resurrect! }

    let(:identity1) { "hostname1:pid:123456" }
    let(:identity2) { "hostname2:pid:123456" }
    let(:logger) { instance_spy(Logger) }

    before do
      allow(described_class::Lock).to receive(:acquire).and_yield

      allow(Sidekiq).to receive(:logger).and_return(logger)
    end

    context "when there is a job to resurrect", :redis => true do
      before do
        Sidekiq.redis do |redis|
          redis.set(identity1, "exists") # Sidekiq info about running sidekiq process

          # Jobs which are in process of being executed
          redis.lpush("inproc:#{identity2}:queue2", "sidekiq_job_hash1")
          redis.lpush("inproc:#{identity2}:queue2", "sidekiq_job_hash2")

          redis.lpush("queue:queue2", "sidekiq_job_hash3") # Job in queue which is not in process

          # Resurrector meta data about in progress processes and the queues they are monitoring
          redis.hset("ultimate:resurrector", identity1, "[\"queue1\",\"queue2\"]")
          redis.hset("ultimate:resurrector", identity2, "[\"queue2\",\"queue3\"]")
        end
      end

      it "resurrects the job" do
        resurrect!

        jobs_in_queue = Sidekiq.redis { |redis| redis.lrange("queue:queue2", 0, -1) }
        expect(jobs_in_queue).to match_array(%w[sidekiq_job_hash1 sidekiq_job_hash2 sidekiq_job_hash3])
        expect(described_class::Lock).to have_received(:acquire).once
      end

      it "calls on_resurrection callback" do
        resurrections = []
        allow(Sidekiq::Ultimate::Configuration.instance).
          to receive(:on_resurrection).and_return(proc { |*args| resurrections << args })

        resurrect!

        expect(resurrections).to contain_exactly(["queue2", 2])
        jobs_in_queue = Sidekiq.redis { |redis| redis.lrange("queue:queue2", 0, -1) }
        expect(jobs_in_queue).to match_array(%w[sidekiq_job_hash1 sidekiq_job_hash2 sidekiq_job_hash3])
      end
    end
  end

  describe "setup!" do
    it "periodically puts current process queues into redis", :redis => true do
      stub_const("Sidekiq::Ultimate::Resurrector::DEFIBRILLATE_INTERVAL", 0.01)
      allow(Sidekiq).to receive(:options).and_return(Sidekiq.options.merge(:queues => %w[queue1 queue2]))

      described_class.setup!

      sidekiq_util.fire_event(:heartbeat)

      sleep(1) # Wait for the timer task to run

      keys = Sidekiq.redis { |redis| redis.hgetall("ultimate:resurrector") }
      expect(keys).to eq({ identity => "[\"queue1\",\"queue2\"]" })

      ObjectSpace.each_object(Concurrent::TimerTask).each(&:shutdown)
    end

    it "unregisters aed on sidekiq shutdown" do
      stub_const("Sidekiq::Ultimate::Resurrector::DEFIBRILLATE_INTERVAL", 0.01)
      described_class.setup!

      sidekiq_util.fire_event(:heartbeat)

      expect { sidekiq_util.fire_event(:shutdown) }.
        to change { ObjectSpace.each_object(Concurrent::TimerTask).count(&:running?) }.from(1).to(0)

      Sidekiq.redis { |redis| redis.del("ultimate:resurrector") }
      sleep(1) # Wait for any other timer to run

      resurrector_key = Sidekiq.redis do |redis|
        if Sidekiq::Ultimate::Resurrector::USE_EXISTS_QUESTION_MARK
          redis.exists?("ultimate:resurrector")
        else
          redis.exists("ultimate:resurrector")
        end
      end
      expect(resurrector_key).to be_falsy
    end
  end
end

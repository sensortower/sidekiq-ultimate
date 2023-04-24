# frozen_string_literal: true

require "sidekiq/ultimate/resurrector"
require "sidekiq/ultimate/use_exists_question_mark"

RSpec.describe Sidekiq::Ultimate::Resurrector do
  let(:identity) { "hostname:pid:123456" }
  let(:sidekiq_util) { Object.new.tap { |o| o.extend Sidekiq::Util } }

  before do
    allow(described_class).to receive(:current_process_identity).and_return(identity)
  end

  def key_exists?(key)
    if Sidekiq::Ultimate::UseExistsQuestionMark.use?
      Sidekiq.redis { |r| r.exists?(key) }
    else
      Sidekiq.redis { |r| r.exists(key) }
    end
  end

  describe ".resurrect!" do
    let(:identity1) { "hostname1:pid:123456" }
    let(:identity2) { "hostname2:pid:123456" }
    let(:logger) { instance_spy(Logger) }

    before do
      allow(described_class::Lock).to receive(:acquire).and_yield

      allow(Sidekiq).to receive(:logger).and_return(logger)
    end

    context "when there is a job to resurrect", :redis => true do
      let(:job_id1) { "2647c4fe13acc692326bd4c1" }
      let(:job_id2) { "2647c4fe13acc692326bd4c2" }
      let(:job_id3) { "2647c4fe13acc692326bd4c3" }
      let(:job_id4) { "2647c4fe13acc692326bd4c4" }
      let(:job_hash1) do
        <<~STRING
          {"class":"TestJob","args":[1],"retry":false,"queue":"default","jid":"#{job_id1}","created_at":1680885347.706304,"enqueued_at":1680885347.706539}
        STRING
      end
      let(:job_hash2) do
        <<~STRING
          {"class":"TestJob","args":[2],"retry":false,"queue":"default","jid":"#{job_id2}","created_at":1680885347.706304,"enqueued_at":1680885347.706539}
        STRING
      end
      let(:job_hash3) do
        <<~STRING
          {"class":"TestJob","args":[3],"retry":false,"queue":"default","jid":"#{job_id3}","created_at":1680885347.706304,"enqueued_at":1680885347.706539}
        STRING
      end
      let(:job_hash4) do
        <<~STRING
          {"class":"TestJob","args":[4],"retry":false,"queue":"default","jid":"#{job_id4}","created_at":1680885347.706304,"enqueued_at":1680885347.706539}
        STRING
      end

      before do
        Sidekiq.redis do |redis|
          redis.set(identity1, "exists") # Sidekiq info about running sidekiq process

          # Jobs which are in process of being executed
          redis.lpush("inproc:#{identity1}:queue2", job_hash1)
          redis.lpush("inproc:#{identity2}:queue2", job_hash2)
          redis.lpush("inproc:#{identity2}:queue2", job_hash3)

          # Job in queue which are not processing yet
          redis.lpush("queue:queue2", job_hash4)

          # Resurrector knows about these processes and their queues
          redis.hset("ultimate:resurrector", identity1, "[\"queue1\",\"queue2\"]")
          redis.hset("ultimate:resurrector", identity2, "[\"queue2\",\"queue3\"]")
        end
      end

      it "resurrects the job" do
        described_class.resurrect!

        jobs_in_queue = Sidekiq.redis { |redis| redis.lrange("queue:queue2", 0, -1) }
        expect(jobs_in_queue).to contain_exactly(job_hash2, job_hash3, job_hash4)
        expect(described_class::Lock).to have_received(:acquire).once
      end

      it "calls on_resurrection callback" do
        resurrections = []
        allow(Sidekiq::Ultimate::Configuration.instance).
          to receive(:on_resurrection).and_return(proc { |*args| resurrections << args })

        described_class.resurrect!

        expect(resurrections).to contain_exactly(["queue2", 2])
        jobs_in_queue = Sidekiq.redis { |redis| redis.lrange("queue:queue2", 0, -1) }
        expect(jobs_in_queue).to contain_exactly(job_hash2, job_hash3, job_hash4)
      end

      it "increments the resurrection counter when enable_resurrection_counter is true" do
        allow(Sidekiq::Ultimate::Configuration.instance).
          to receive(:enable_resurrection_counter).and_return(-> { true })

        described_class.resurrect!

        counter1 = Sidekiq.redis { |r| r.get("ultimate:resurrector:counter:jid:2647c4fe13acc692326bd4c2") }
        counter1_ttl = Sidekiq.redis { |r| r.ttl("ultimate:resurrector:counter:jid:2647c4fe13acc692326bd4c2") }
        counter2 = Sidekiq.redis { |r| r.get("ultimate:resurrector:counter:jid:2647c4fe13acc692326bd4c3") }
        counter2_ttl = Sidekiq.redis { |r| r.ttl("ultimate:resurrector:counter:jid:2647c4fe13acc692326bd4c3") }

        expect(counter1).to eq("1")
        expect(counter1_ttl).to be_within(5).of(86_400)
        expect(counter2).to eq("1")
        expect(counter2_ttl).to be_within(5).of(86_400)
      end

      it "does not increment the resurrection counter when enable_resurrection_counter is false" do
        allow(Sidekiq::Ultimate::Configuration.instance).
          to receive(:enable_resurrection_counter).and_return(-> { false })

        described_class.resurrect!

        expect(key_exists?("ultimate:resurrector:counter:jid:2647c4fe13acc692326bd4c2")).to be_falsy
        expect(key_exists?("ultimate:resurrector:counter:jid:2647c4fe13acc692326bd4c3")).to be_falsy
      end

      it "does not increment the resurrection counter when enable_resurrection_counter is not set" do
        described_class.resurrect!

        expect(key_exists?("ultimate:resurrector:counter:jid:2647c4fe13acc692326bd4c2")).to be_falsy
        expect(key_exists?("ultimate:resurrector:counter:jid:2647c4fe13acc692326bd4c3")).to be_falsy
      end

      it "executes resurrection_counter Proc on each resurrection event" do
        enable_resurrection_counter = true
        allow(Sidekiq::Ultimate::Configuration.instance).
          to receive(:enable_resurrection_counter).and_return(-> { enable_resurrection_counter })

        described_class.resurrect!

        counter1 = Sidekiq.redis { |r| r.get("ultimate:resurrector:counter:jid:2647c4fe13acc692326bd4c2") }
        counter2 = Sidekiq.redis { |r| r.get("ultimate:resurrector:counter:jid:2647c4fe13acc692326bd4c3") }

        expect(counter1).to eq("1")
        expect(counter2).to eq("1")

        # Refresh the state
        Sidekiq.redis do |r|
          r.del("ultimate:resurrector:counter:jid:2647c4fe13acc692326bd4c2")
          r.del("ultimate:resurrector:counter:jid:2647c4fe13acc692326bd4c3")

          r.lpush("inproc:#{identity2}:queue2", job_hash2)
          r.lpush("inproc:#{identity2}:queue2", job_hash3)

          r.hset("ultimate:resurrector", identity1, "[\"queue1\",\"queue2\"]")
          r.hset("ultimate:resurrector", identity2, "[\"queue2\",\"queue3\"]")
        end

        enable_resurrection_counter = false

        described_class.resurrect!

        counter1 = Sidekiq.redis { |r| r.get("ultimate:resurrector:counter:jid:2647c4fe13acc692326bd4c2") }
        counter2 = Sidekiq.redis { |r| r.get("ultimate:resurrector:counter:jid:2647c4fe13acc692326bd4c3") }

        expect(counter1).to be_nil
        expect(counter2).to be_nil
      end
    end
  end

  describe "setup!" do
    after do
      ObjectSpace.each_object(Concurrent::TimerTask).each(&:shutdown)

      Sidekiq.options[:lifecycle_events].each_value(&:clear)
    end

    it "periodically puts current process queues into redis", :redis => true do
      stub_const("Sidekiq::Ultimate::Resurrector::DEFIBRILLATE_INTERVAL", 0.01)
      allow(Sidekiq).to receive(:options).and_return(Sidekiq.options.merge(:queues => %w[queue1 queue2]))

      described_class.setup!

      sidekiq_util.fire_event(:heartbeat)

      sleep(0.5) # Wait for the timer task to run

      keys = Sidekiq.redis { |redis| redis.hgetall("ultimate:resurrector") }
      expect(keys).to eq({ identity => "[\"queue1\",\"queue2\"]" })
    end

    it "unregisters heartbeat_timer_task on sidekiq shutdown" do
      stub_const("Sidekiq::Ultimate::Resurrector::DEFIBRILLATE_INTERVAL", 0.01)
      described_class.setup!
      timer_task = Sidekiq::Ultimate::Resurrector::HeartbeatTimerTask

      expect { sidekiq_util.fire_event(:heartbeat) }.
        to change { ObjectSpace.each_object(timer_task).count(&:running?) }.from(0).to(1)

      expect { sidekiq_util.fire_event(:shutdown) }.
        to change { ObjectSpace.each_object(timer_task).count(&:running?) }.from(1).to(0)

      Sidekiq.redis { |redis| redis.del("ultimate:resurrector") }
      sleep(0.5) # Wait for any other timer to run

      expect(key_exists?("ultimate:resurrector")).to be_falsy
    end

    it "unregisters resurrector_timer_task on sidekiq shutdown" do
      stub_const("Sidekiq::Ultimate::Resurrector::RESURRECTOR_INTERVAL", 0.01)
      described_class.setup!
      timer_task = Sidekiq::Ultimate::Resurrector::ResurrectorTimerTask

      expect { sidekiq_util.fire_event(:startup) }.
        to change { ObjectSpace.each_object(timer_task).count(&:running?) }.from(0).to(1)

      expect { sidekiq_util.fire_event(:shutdown) }.
        to change { ObjectSpace.each_object(timer_task).count(&:running?) }.from(1).to(0)

      Sidekiq.redis { |redis| redis.del("ultimate:resurrector") }
      sleep(0.5) # Wait for any other timer to run

      expect(key_exists?("ultimate:resurrector")).to be_falsy
    end
  end
end

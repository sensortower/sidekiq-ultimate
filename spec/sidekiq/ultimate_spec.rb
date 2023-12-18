# frozen_string_literal: true

require "sidekiq/cli"
require "sidekiq/ultimate"
require "sidekiq/ultimate/fetch"

RSpec.describe Sidekiq::Ultimate do
  describe ".setup!" do
    let(:communicator) { instance_spy(Sidekiq::Throttled::Communicator) }
    let(:queues_pauser) { instance_spy(Sidekiq::Throttled::QueuesPauser) }
    let(:resurrector) { class_spy(Sidekiq::Ultimate::Resurrector) }
    let(:empty_queues) { class_spy(Sidekiq::Ultimate::EmptyQueues) }

    it "sets up reliable fetch and friends" do
      allow(Sidekiq::Throttled::Communicator).to receive(:instance).and_return(communicator)
      allow(Sidekiq::Throttled::QueuesPauser).to receive(:instance).and_return(queues_pauser)
      stub_const(Sidekiq::Ultimate::Resurrector.name, resurrector)
      stub_const(Sidekiq::Ultimate::EmptyQueues.name, empty_queues)

      described_class.setup!

      expect(Sidekiq[:fetch]).to be_instance_of(Sidekiq::Ultimate::Fetch)
      expect(communicator).to have_received(:setup!)
      expect(queues_pauser).to have_received(:setup!)
      expect(resurrector).to have_received(:setup!)
      expect(empty_queues).to have_received(:setup!)
    end
  end
end

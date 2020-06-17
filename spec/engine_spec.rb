# frozen_string_literal: true

require "spec_helper"

describe Vessel::Engine do
  let(:crawler_class)  { Class.new(Vessel::Cargo) }
  let(:handler)        { Proc.new {} }
  let(:engine)         { described_class.new(crawler_class, &handler) }

  describe '.new' do
    it { expect( engine.crawler_class ).to be(crawler_class) }
    it { expect( engine.settings      ).to be(crawler_class.settings) }
    it { expect( engine.middleware    ).to be(handler) }
    it { expect( engine.scheduler     ).to be_a(Vessel::Scheduler) }
  end

  describe '#run' do
    let(:page)     { double(Ferrum::Page) }
    let(:request)  { Vessel::Request.new }

    before do
      # stub out scheduler
      allow( engine.scheduler ).to receive(:post)
      allow( engine.scheduler ).to receive(:stop)
      # stub out handle call (tested below)
      allow( engine ).to receive(:handle)
      # put something in the queue
      engine.scheduler.queue << [page, request]
    end

    it 'posts start requests' do
      engine.run

      expect( engine.scheduler ).to have_received(:post).with(
        instance_of(Vessel::Request)
      )
    end

    it 'processes queue until empty' do
      expect { engine.run }.to change( engine.scheduler.queue, :length ).from(1).to(0)
    end

    it 'handles pages found in queue' do
      engine.run

      expect( engine ).to have_received(:handle).with(page, [request.method])
    end

    it 'stops the scheduler when done' do
      engine.run

      expect( engine.scheduler ).to have_received(:stop)
    end

    it 're-raises exception found in queue' do
      engine.scheduler.queue << (error = StandardError.new)

      expect { engine.run }.to raise_error(error)
    end

    it 'ensures the scheduler is stopped' do
      engine.scheduler.queue << (error = StandardError.new)
      expect { engine.run }.to raise_error(error)
      expect( engine.scheduler ).to have_received(:stop)
    end
  end

  describe '#handle' do
    let(:crawler) { crawler_class.new(page) }
    let(:page)    { double(Ferrum::Page) }
    let(:result)  { double('Crawler#parse result') }
    let(:request) { Vessel::Request.new }

    before do
      allow(crawler_class).to receive(:new).and_return(crawler)
      allow(crawler).to receive(:parse).and_yield(request).and_yield(result)
      allow(engine.middleware).to receive(:call)
      allow(engine.scheduler).to receive(:post)
      allow(page).to receive(:close)

      engine.handle(page, [:parse])
    end

    it 'creates a new crawler instance and calls #parse to process the page' do
      expect( crawler_class ).to have_received(:new).with(page)
      expect( crawler ).to have_received(:parse)
    end

    it 'calls block handler or middleware with #parse results' do
      expect( engine.middleware ).to have_received(:call).with(result)
    end

    it 'schedules new requests emitted by #parse' do
      expect( engine.scheduler ).to have_received(:post).with(request)
    end

    it 'closes the page when done' do
      expect( page ).to have_received(:close)
    end
  end

end

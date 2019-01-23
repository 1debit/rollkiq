RSpec.describe Rollbar::Sidekiq do
  context '#skip_report?' do
    let(:skip_report?) { described_class.skip_report?(job_hash, error) }
    let(:job_hash) {
      {
        'retry' => true,
        'retry_count' => retry_count,
        'class' => class_name
      }
    }
    let(:class_name) { nil}
    let(:error) { nil }
    let(:sidekiq_threshold) { nil }
    let(:retry_count) { nil }

    before do
      allow(Rollbar).to receive_message_chain(
        :configuration, :sidekiq_threshold
      ).and_return(sidekiq_threshold)
    end

    context '#notifiy_on_retry_number' do
      let(:class_name) { 'FakeWorker' }
      let(:fake_worker) {
        double('FakeWorker', notifiy_on_retry_number: notifiy_on_retry_number)
      }

      before do
        allow(
          described_class
        ).to receive(
          :const_get
        ).with(
          job_hash['class']
        ).and_return(fake_worker)
      end

      context 'when not implemented' do
        let(:fake_worker) {
          double('FakeWorker')
        }

        before do
          allow(
            fake_worker
          ).to receive(
            :notifiy_on_retry_number
          ).and_raise(NoMethodError)
        end

        it { expect(skip_report?).to be(false) }
      end

      context 'when retry count matches' do
        let(:retry_count) { 0 }
        context 'when an integer' do
          let(:notifiy_on_retry_number) { 1 }

          it { expect(skip_report?).to be(false) }
        end

        context 'when an array' do
          let(:notifiy_on_retry_number) { [1] }

          it { expect(skip_report?).to be(false) }
        end
      end

      context 'when retry count does not match' do
        let(:retry_count) { 1 }
        context 'when an integer' do
          let(:notifiy_on_retry_number) { 1 }

          it { expect(skip_report?).to be(true) }
        end

        context 'when an array' do
          let(:notifiy_on_retry_number) { [1] }

          it { expect(skip_report?).to be(true) }
        end
      end
    end

    context 'default behavior' do
      context 'when retry_count nil' do
        let(:retry_count) { nil }

        it { expect(skip_report?).to be(false) }
      end

      context 'when retry_count greater than equal sidekiq_threshold' do
        let(:retry_count) { 0 }

        it { expect(skip_report?).to be(false) }
      end

      context 'when retry_count less than sidekiq_threshold' do
        let(:retry_count) { 0 }
        let(:sidekiq_threshold) { 2 }

        it { expect(skip_report?).to be(true) }
      end

      context 'when job_hash is nil' do
        let(:job_hash) { nil }

        it { expect(skip_report?).to be(false) }
      end

      context 'when retry is false' do
        let(:job_hash) { {'retry' => false} }

        it { expect(skip_report?).to be(false) }
      end
    end
  end
end

RSpec.describe Rollbar::Sidekiq do
  context '.handle_exception' do
    let(:handle_exception) {
      described_class.handle_exception(ctx_hash, StandardError)
    }
    let(:ctx_hash) { { job: job_hash } }
    let(:job_hash) {
      {
        'class' => 'class_name',
        'queue' => 'queue_name'
      }
    }

    let(:params) { job_hash }
    let(:person_scope) {
      {
        id: nil,
        email: nil,
        username: nil
      }
    }
    let(:scope) {
      {
        framework: "Sidekiq: 1.0.0",
        context: 'class_name',
        queue: 'queue_name',
        request: {
          params: params
        },
        person: person_scope
      }
    }
    let(:scope_double) { double('Scope', error: nil) }

    before do
      stub_const('Sidekiq::VERSION', '1.0.0')
      allow(described_class).to receive(:const_get)
    end

    it 'sends a rollbar' do
      expect(Rollbar).to receive(:scope).with(scope).and_return(scope_double)
      expect(scope_double).to receive(:error).with(
        StandardError, use_exception_level_filters: true
      )

      handle_exception
    end

    context 'user' do
      let(:fake_worker_class) {
        double(
          'FakeWorkerClass', new: double(
            'FakeWorker', person: double(
              'Person', person_scope
            )
          )
        )
      }
      let(:person_scope) {
        {
          id: 'id',
          email: 'email',
          username: 'username'
        }
      }
      before do
        allow(described_class).to receive(:const_get).with(
          job_hash['class']
        ).and_return(fake_worker_class)
      end

      it 'sends a rollbar with person' do
        expect(Rollbar).to receive(:scope).with(scope).and_return(scope_double)
        expect(scope_double).to receive(:error).with(
          StandardError, use_exception_level_filters: true
        )

        handle_exception
      end

      context 'person does not implement method' do
        let(:fake_worker_class) {
          double(
            'FakeWorkerClass', new: double(
              'FakeWorker', person: person_double
            )
          )
        }
        let(:person_double) {
          double(
            'Person',
            id: 'id',
            email: 'email'
          )
        }
        let(:person_scope) {
          {
            id: 'id',
            email: 'email',
            username: nil
          }
        }

        before do
          allow(person_double).to receive(:username).and_raise(NoMethodError)
        end

        it 'sets unimplemented methods to nil' do
          expect(Rollbar).to receive(:scope).with(scope).and_return(scope_double)
          expect(scope_double).to receive(:error).with(
            StandardError, use_exception_level_filters: true
          )

          handle_exception
        end
      end
    end

    context 'scrubber' do
      let(:scrubber_options) {
        {
          params: job_hash,
          config: Rollbar.configuration.scrub_fields
        }
      }
      before do
        expect(
          Rollbar::Scrubbers::Params
        ).to receive(
          :call
        ).with(scrubber_options).and_return(job_hash)
      end

      it 'calls the scrubber' do
        expect(Rollbar).to receive(:scope).with(scope).and_return(scope_double)
        expect(scope_double).to receive(:error).with(
          StandardError, use_exception_level_filters: true
        )

        handle_exception
      end
    end

    context 'blacklist' do
      let(:job_hash) {
        {
          'class' => 'class_name',
          'queue' => 'queue_name',
          'blacklisted_field' => 'blacklisted_field'
        }
      }
      let(:params) {
        {
          'class' => 'class_name',
          'queue' => 'queue_name'
        }
      }

      before do
        stub_const('Rollbar::Sidekiq::PARAM_BLACKLIST', ['blacklisted_field'])
      end

      it 'sends a rollbar without blacklist param' do
        expect(Rollbar).to receive(:scope).with(scope).and_return(scope_double)
        expect(scope_double).to receive(:error).with(
          StandardError, use_exception_level_filters: true
        )

        handle_exception
      end
    end
  end

  context '#skip_report?' do
    let(:skip_report?) {
      described_class.new(ctx_hash, error).send(:skip_report?)
    }
    let(:ctx_hash) {
      {
        job: job_hash
      }
    }
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

    context '#notify_on_failure_number' do
      let(:class_name) { 'FakeWorker' }
      let(:fake_worker_class) {
        double('FakeWorkerClass', new: fake_worker)
      }
      let(:fake_worker) {
        double('FakeWorker', notify_on_failure_number: notify_on_failure_number)
      }

      before do
        allow(
          described_class
        ).to receive(
          :const_get
        ).with(
          job_hash['class']
        ).and_return(fake_worker_class)
      end

      context 'when not implemented' do
        let(:fake_worker) {
          double('FakeWorker')
        }

        before do
          allow(
            fake_worker
          ).to receive(
            :notify_on_failure_number
          ).and_raise(NoMethodError)
        end

        it { expect(skip_report?).to be(false) }
      end

      context 'when retry count matches' do
        let(:retry_count) { 0 }
        context 'when an integer' do
          let(:notify_on_failure_number) { 1 }

          it { expect(skip_report?).to be(false) }
        end

        context 'when an array' do
          let(:notify_on_failure_number) { [1] }

          it { expect(skip_report?).to be(false) }
        end
      end

      context 'when retry count does not match' do
        let(:retry_count) { 1 }
        context 'when an integer' do
          let(:notify_on_failure_number) { 1 }

          it { expect(skip_report?).to be(true) }
        end

        context 'when an array' do
          let(:notify_on_failure_number) { [1] }

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

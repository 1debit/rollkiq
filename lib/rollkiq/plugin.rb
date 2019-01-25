require 'rollbar/plugins/sidekiq/plugin'

module Rollbar
  class Sidekiq
    attr_reader :job_hash, :error

    def initialize(ctx_hash, error)
      @ctx_hash = ctx_hash
      @job_hash = ctx_hash.fetch(:job, nil)
      @error = error
    end

    def self.handle_exception(ctx_hash, error)
      new(ctx_hash, error).handle_exception
    end

    def handle_exception
      return if skip_report?

      Rollbar.scope(scope).error(error, use_exception_level_filters: true)
    end

    private

    def skip_report?
      return false if job_hash.nil?
      return false unless job_hash['retry']

      notify_on_failure_number.nil? ? skip_globally? : skip_override?
    end

    def scope
      {
        framework: "Sidekiq: #{::Sidekiq::VERSION}",
        context: job_hash&.fetch('class', nil),
        queue: job_hash&.fetch('queue', nil),
        request: request_scope,
        person: person_scope
      }
    end

    def request_scope
      {
        params: sanitized_params
      }
    end

    def sanitized_params
      scrub_params(non_blacklisted_params)
    end

    def scrub_params(params)
      options = {
        params: params,
        config: Rollbar.configuration.scrub_fields
      }

      Rollbar::Scrubbers::Params.call(options)
    end

    def non_blacklisted_params
      job_hash&.reject { |key| PARAM_BLACKLIST.include?(key) }
    end

    def person_scope
      {
        id: person_id,
        email: person_email,
        username: person_username
      }
    end

    def person_id
      person.id rescue nil
    end

    def person_email
      person.email rescue nil
    end

    def person_username
      person.username rescue nil
    end

    def person
      worker_instance.person(*job_hash['args']) rescue nil
    end

    def skip_globally?
      retry_count < global_threshold
    end

    def skip_override?
      case
      when notify_on_failure_number.is_a?(Integer)
        notify_on_failure_number != retry_count
      when notify_on_failure_number.is_a?(Array)
        !notify_on_failure_number.include?(retry_count)
      end
    end

    def notify_on_failure_number
      @notify_on_failure_number ||= worker_instance.notify_on_failure_number rescue nil
    end

    def worker_instance
      self.class.const_get(job_hash['class']).new rescue nil
    end

    def global_threshold
      Rollbar.configuration.sidekiq_threshold.to_i
    end

    def retry_count
      # when rollbar middleware catches, sidekiq's retry_job processor hasn't set
      # the retry_count for the current job yet, so adding 1 gives the actual retry count
      job_hash.fetch('retry_count', -1).to_i + 1
    end
  end
end

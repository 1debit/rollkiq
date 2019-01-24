require 'rollbar/plugins/sidekiq/plugin'

module Rollbar
  class Sidekiq
    attr_reader :job_hash, :error

    def initialize(job_hash, error)
      @job_hash = job_hash
      @error = error
    end

    def self.skip_report?(job_hash, error)
      return false if job_hash.nil?

      new(job_hash, error).skip_report?
    end

    def skip_report?
      return false unless job_hash['retry']

      notifiy_on_retry_number.nil? ? skip_globally? : skip_override?
    end

    private

    def skip_globally?
      retry_count < global_threshold
    end

    def skip_override?
      case
      when notifiy_on_retry_number.is_a?(Integer)
        notifiy_on_retry_number != retry_count
      when notifiy_on_retry_number.is_a?(Array)
        !notifiy_on_retry_number.include?(retry_count)
      end
    end

    def notifiy_on_retry_number
      @notifiy_on_retry_number ||= worker_instance.notifiy_on_retry_number rescue nil
    end

    def worker_instance
      self.class.const_get(job_hash['class']).new rescue nil
    end

    def global_threshold
      ::Rollbar.configuration.sidekiq_threshold.to_i
    end

    def retry_count
      # when rollbar middleware catches, sidekiq's retry_job processor hasn't set
      # the retry_count for the current job yet, so adding 1 gives the actual retry count
      job_hash.fetch('retry_count', -1).to_i + 1
    end
  end
end

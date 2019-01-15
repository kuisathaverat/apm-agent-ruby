# frozen_string_literal: true

require 'elastic_apm/metricset'

module ElasticAPM
  # @api private
  module Metrics
    def self.new(config, &block)
      Collector.new(config, &block)
    end

    def self.platform
      @platform ||= Gem::Platform.local.os.to_sym
    end

    # @api private
    class Collector
      include Logging

      TIMEOUT_INTERVAL = 5 # seconds

      def initialize(config, &block)
        @config = config
        @samplers = [CpuMem].map { |kls| kls.new(config) }
        @callback = block
      end

      attr_reader :config, :samplers, :callback

      # rubocop:disable Metrics/MethodLength
      def start
        @timer_task = Concurrent::TimerTask.execute(
          run_now: true,
          execution_interval: config.metrics_interval,
          timeout_interval: TIMEOUT_INTERVAL
        ) do
          begin
            collect_and_send
            true
          rescue StandardError => e
            error 'Error while collecting metrics: %e', e.inspect
            debug { e.backtrace.join("\n") }
            false
          end
        end
      end
      # rubocop:enable Metrics/MethodLength

      def stop
        @timer_task.shutdown
      end

      def collect_and_send
        metricset = Metricset.new(**collect)
        return if metricset.empty?

        callback.call(metricset)
      end

      def collect
        samplers.each_with_object({}) do |sampler, samples|
          next unless (sample = sampler.collect)
          samples.merge!(sample)
        end
      end
    end
  end
end

require 'elastic_apm/metrics/cpu_mem'

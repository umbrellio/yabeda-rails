# frozen_string_literal: true

require "yabeda"
require "rails"
require "yabeda/rails/railtie"

module Yabeda
  # Minimal set of Rails-specific metrics for using with Yabeda
  module Rails
    TAGS = %i[controller action status format method].freeze
    DEFAULT_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10].freeze
    LONG_RUNNING_REQUEST_BUCKETS = [*DEFAULT_BUCKETS, 30, 60, 120, 300, 600].freeze

    MUTEX = Mutex.new

    class << self
      def controller_handlers
        @controller_handlers ||= []
      end

      def on_controller_action(&block)
        controller_handlers << block
      end

      # Declare metrics and install event handlers for collecting themya
      # rubocop: disable Metrics/MethodLength, Metrics/BlockLength, Metrics/AbcSize
      def install!
        MUTEX.synchronize do
          return if @installed

          Yabeda.configure do
            group :rails

            counter :requests_total do
              comment "A counter of the total number of HTTP requests rails processed."
              tags TAGS
            end

            histogram :request_duration do
              comment "A histogram of the response latency."
              buckets LONG_RUNNING_REQUEST_BUCKETS
              unit :seconds
              tags TAGS
            end

            histogram :view_runtime do
              comment "A histogram of the view rendering time."
              buckets LONG_RUNNING_REQUEST_BUCKETS
              unit :seconds
              tags TAGS
            end

            histogram :db_query_count do
              comment "A histogram of DB query count."
              buckets [1, 10, 25, 50, 100, 250, 500, 1000]
              tags TAGS
            end

            histogram :db_runtime do
              comment "A histogram of DB execution time."
              buckets LONG_RUNNING_REQUEST_BUCKETS
              unit :seconds
              tags TAGS
            end

            histogram :cpu_time do
              comment "A histogram of CPU time."
              buckets DEFAULT_BUCKETS
              tags TAGS
            end
          end

          subscribe!

          on_controller_action do |event, labels|
            Yabeda.rails_requests_total.increment(labels)
            Yabeda.rails_request_duration.measure(labels, ms2s(event.duration))
            Yabeda.rails_view_runtime.measure(labels, ms2s(event.payload[:view_runtime]))
            Yabeda.rails_db_query_count.measure(labels, event.payload[:db_query_count])
            Yabeda.rails_db_runtime.measure(labels, ms2s(event.payload[:db_runtime]))
            Yabeda.rails_cpu_time.measure(labels, event.cpu_time)
          end

          @installed = true
        end
      end
      # rubocop: enable Metrics/MethodLength, Metrics/BlockLength, Metrics/AbcSize

      def subscribe!
        ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*args|
          event = ActiveSupport::Notifications::Event.new(*args)
          process_event!(event)
        end
      end

      def process_event!(event)
        labels = generate_labels(event)
        labels.merge!(event.payload.slice(*Yabeda.default_tags.keys - labels.keys))

        controller_handlers.each do |handler|
          handler.call(event, labels)
        end
      end

      def generate_labels(event)
        {
          controller: event.payload[:params]["controller"],
          action: event.payload[:params]["action"],
          status: event.payload[:status],
          format: event.payload[:format],
          method: event.payload[:method].downcase,
        }
      end

      def ms2s(milliseconds)
        (milliseconds.to_f / 1000).round(3)
      end
    end
  end
end

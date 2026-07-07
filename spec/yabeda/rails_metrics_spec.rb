# frozen_string_literal: true

RSpec.describe Yabeda::Rails do
  def instrument(&block)
    block ||= proc {}
    ActiveSupport::Notifications.instrument(
      "process_action.action_controller", payload, &block
    )
  end

  let(:payload) do
    {
      params: { "controller" => "users", "action" => "show" },
      controller: "UsersController",
      action: "show",
      status: 200,
      format: :html,
      method: "GET",
      view_runtime: 10.0,
      db_runtime: 5.0,
      db_query_count: 3,
    }
  end

  let(:labels) do
    { controller: "users", action: "show", status: 200, format: :html, method: "get" }
  end

  it "increments requests and allocations counters with correct labels" do
    expect { instrument { Array.new(100) { "x" } } }
      .to increment_yabeda_counter(Yabeda.rails.requests_total).with(labels => 1)
      .and increment_yabeda_counter(Yabeda.rails.allocations_total).with_tags(labels)
      .and measure_yabeda_histogram(Yabeda.rails.request_duration).with_tags(labels)
      .and measure_yabeda_histogram(Yabeda.rails.cpu_time).with_tags(labels)
  end

  it "does not increment allocation_bytes without the Event patch" do
    expect { instrument }.not_to increment_yabeda_counter(Yabeda.rails.allocation_bytes)
  end

  context "when the Event is patched with malloc_increase_bytes" do
    before do
      # Emulates the ActiveSupport::Notifications::Event patch from umbrellio-utils
      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(ActiveSupport::Notifications::Event)
        .to receive(:malloc_increase_bytes).and_return(4096)
      # rubocop:enable RSpec/AnyInstance
    end

    it "increments allocation_bytes" do
      expect { instrument }
        .to increment_yabeda_counter(Yabeda.rails.allocation_bytes).with(labels => 4096)
    end
  end
end

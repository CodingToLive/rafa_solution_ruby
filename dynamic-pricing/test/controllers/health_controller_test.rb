require "test_helper"

class Api::V1::HealthControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
  end

  test "empty cache shows zero coverage" do
    get api_v1_health_url

    assert_response :success
    json = JSON.parse(@response.body)

    assert_equal "ok", json["status"]
    assert_equal PricingConstants::ALL_COMBINATIONS.size, json["cache"]["total_combinations"]
    assert_equal 0, json["cache"]["cached_entries"]
    assert_equal "0.0%", json["cache"]["coverage"]
    assert_equal 0, json["upstream_budget"]["calls_today"]
    assert_equal PricingUpstreamBudget::LIMIT, json["upstream_budget"]["limit"]
  end

  test "partial cache shows correct coverage" do
    # Cache 3 entries
    3.times do |i|
      combo = PricingConstants::ALL_COMBINATIONS[i]
      key = PricingConstants.cache_key(period: combo[:period], hotel: combo[:hotel], room: combo[:room])
      Rails.cache.write(key, 10000 + i)
    end

    get api_v1_health_url

    assert_response :success
    json = JSON.parse(@response.body)

    assert_equal 3, json["cache"]["cached_entries"]
    expected_pct = ((3.0 / PricingConstants::ALL_COMBINATIONS.size) * 100).round(1)
    assert_equal "#{expected_pct}%", json["cache"]["coverage"]
  end
end

require "test_helper"

class PricingUpstreamBudgetTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
  end

  test "first call returns 1" do
    result = PricingUpstreamBudget.consume!
    assert_equal 1, result
  end

  test "multiple calls increment correctly" do
    PricingUpstreamBudget.consume!
    PricingUpstreamBudget.consume!
    result = PricingUpstreamBudget.consume!

    assert_equal 3, result
  end

  test "exceeding limit raises QuotaExceeded" do
    key = PricingUpstreamBudget.key_for_today
    Rails.cache.write(key, PricingUpstreamBudget::LIMIT, expires_in: 24.hours)

    assert_raises(PricingUpstreamBudget::QuotaExceeded) do
      PricingUpstreamBudget.consume!
    end
  end

  test "counter is decremented after exceeding limit" do
    key = PricingUpstreamBudget.key_for_today
    Rails.cache.write(key, PricingUpstreamBudget::LIMIT, expires_in: 24.hours)

    begin
      PricingUpstreamBudget.consume!
    rescue PricingUpstreamBudget::QuotaExceeded
      # expected
    end

    assert_equal PricingUpstreamBudget::LIMIT, Rails.cache.read(key)
  end
end

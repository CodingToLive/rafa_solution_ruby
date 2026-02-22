require "test_helper"

class PricingCacheRefreshJobTest < ActiveJob::TestCase
  setup do
    Rails.cache.clear
  end

  test "happy path caches all rates" do
    rates = PricingConstants::ALL_COMBINATIONS.map { |combo|
      { 'period' => combo[:period], 'hotel' => combo[:hotel], 'room' => combo[:room], 'rate' => 10000 }
    }
    mock_response = OpenStruct.new(success?: true, parsed_response: { 'rates' => rates })

    RateApiClient.stub(:get_all_rates, mock_response) do
      PricingCacheRefreshJob.perform_now
    end

    PricingConstants::ALL_COMBINATIONS.each do |combo|
      key = PricingConstants.cache_key(period: combo[:period], hotel: combo[:hotel], room: combo[:room])
      assert_equal 10000, Rails.cache.read(key), "Expected cache entry for #{key}"
    end
  end

  test "skips entries missing rate key" do
    rates = [
      { 'period' => 'Summer', 'hotel' => 'FloatingPointResort', 'room' => 'SingletonRoom', 'rate' => 15000 },
      { 'period' => 'Winter', 'hotel' => 'GitawayHotel', 'room' => 'BooleanTwin' }
    ]
    mock_response = OpenStruct.new(success?: true, parsed_response: { 'rates' => rates })

    RateApiClient.stub(:get_all_rates, mock_response) do
      PricingCacheRefreshJob.perform_now
    end

    valid_key = PricingConstants.cache_key(period: 'Summer', hotel: 'FloatingPointResort', room: 'SingletonRoom')
    missing_key = PricingConstants.cache_key(period: 'Winter', hotel: 'GitawayHotel', room: 'BooleanTwin')

    assert_equal 15000, Rails.cache.read(valid_key)
    assert_nil Rails.cache.read(missing_key)
  end

  test "normalizes string rate to integer" do
    rates = [
      { 'period' => 'Summer', 'hotel' => 'FloatingPointResort', 'room' => 'SingletonRoom', 'rate' => '15000' }
    ]
    mock_response = OpenStruct.new(success?: true, parsed_response: { 'rates' => rates })

    RateApiClient.stub(:get_all_rates, mock_response) do
      PricingCacheRefreshJob.perform_now
    end

    key = PricingConstants.cache_key(period: 'Summer', hotel: 'FloatingPointResort', room: 'SingletonRoom')
    cached = Rails.cache.read(key)

    assert_equal 15000, cached
    assert_kind_of Integer, cached
  end

  test "API error does not cache anything" do
    mock_response = OpenStruct.new(success?: false, parsed_response: { 'error' => 'server error' })

    RateApiClient.stub(:get_all_rates, mock_response) do
      PricingCacheRefreshJob.perform_now
    end

    PricingConstants::ALL_COMBINATIONS.each do |combo|
      key = PricingConstants.cache_key(period: combo[:period], hotel: combo[:hotel], room: combo[:room])
      assert_nil Rails.cache.read(key)
    end
  end

  test "invalid payload does not cache anything" do
    mock_response = OpenStruct.new(success?: true, parsed_response: "not a hash")

    RateApiClient.stub(:get_all_rates, mock_response) do
      PricingCacheRefreshJob.perform_now
    end

    PricingConstants::ALL_COMBINATIONS.each do |combo|
      key = PricingConstants.cache_key(period: combo[:period], hotel: combo[:hotel], room: combo[:room])
      assert_nil Rails.cache.read(key)
    end
  end

  test "quota exceeded skips API call" do
    PricingUpstreamBudget.stub(:consume!, ->(*) { raise PricingUpstreamBudget::QuotaExceeded, "over limit" }) do
      PricingCacheRefreshJob.perform_now
    end

    PricingConstants::ALL_COMBINATIONS.each do |combo|
      key = PricingConstants.cache_key(period: combo[:period], hotel: combo[:hotel], room: combo[:room])
      assert_nil Rails.cache.read(key)
    end
  end

  test "generic crash enqueues retry" do
    RateApiClient.stub(:get_all_rates, ->(*) { raise RuntimeError, "boom" }) do
      assert_enqueued_with(job: PricingCacheRefreshJob) do
        PricingCacheRefreshJob.perform_now
      end
    end
  end
end

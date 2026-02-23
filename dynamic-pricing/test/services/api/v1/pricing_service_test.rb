require "test_helper"

class Api::V1::PricingServiceTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
    @period = "Summer"
    @hotel = "FloatingPointResort"
    @room = "SingletonRoom"
  end

  test "cache hit returns cached value without calling API" do
    key = PricingConstants.cache_key(period: @period, hotel: @hotel, room: @room)
    Rails.cache.write(key, 15000, expires_in: 5.minutes)

    # If API is called, this will raise — proving it was never called
    RateApiClient.stub(:get_rate, ->(*) { raise "API should not be called" }) do
      service = Api::V1::PricingService.new(period: @period, hotel: @hotel, room: @room)
      service.run

      assert service.valid?
      assert_equal 15000, service.result
    end
  end

  test "cache miss calls API and caches result" do
    mock_parsed = {
      'rates' => [
        { 'period' => @period, 'hotel' => @hotel, 'room' => @room, 'rate' => 15000 }
      ]
    }
    mock_response = OpenStruct.new(success?: true, parsed_response: mock_parsed)

    RateApiClient.stub(:get_rate, mock_response) do
      service = Api::V1::PricingService.new(period: @period, hotel: @hotel, room: @room)
      service.run

      assert service.valid?
      assert_equal 15000.0, service.result

      key = PricingConstants.cache_key(period: @period, hotel: @hotel, room: @room)
      assert_equal 15000.0, Rails.cache.read(key)
    end
  end

  test "string rate is normalized to float" do
    mock_parsed = {
      'rates' => [
        { 'period' => @period, 'hotel' => @hotel, 'room' => @room, 'rate' => '15000' }
      ]
    }
    mock_response = OpenStruct.new(success?: true, parsed_response: mock_parsed)

    RateApiClient.stub(:get_rate, mock_response) do
      service = Api::V1::PricingService.new(period: @period, hotel: @hotel, room: @room)
      service.run

      assert service.valid?
      assert_equal 15000.0, service.result
      assert_kind_of Float, service.result
    end
  end

  test "decimal rate is preserved" do
    mock_parsed = {
      'rates' => [
        { 'period' => @period, 'hotel' => @hotel, 'room' => @room, 'rate' => '150.50' }
      ]
    }
    mock_response = OpenStruct.new(success?: true, parsed_response: mock_parsed)

    RateApiClient.stub(:get_rate, mock_response) do
      service = Api::V1::PricingService.new(period: @period, hotel: @hotel, room: @room)
      service.run

      assert service.valid?
      assert_equal 150.5, service.result
    end
  end

  test "null rate returns bad_gateway" do
    mock_parsed = {
      'rates' => [
        { 'period' => @period, 'hotel' => @hotel, 'room' => @room, 'rate' => nil }
      ]
    }
    mock_response = OpenStruct.new(success?: true, parsed_response: mock_parsed)

    RateApiClient.stub(:get_rate, mock_response) do
      service = Api::V1::PricingService.new(period: @period, hotel: @hotel, room: @room)
      service.run

      assert_not service.valid?
      assert_equal :bad_gateway, service.error_status
      assert_includes service.errors.first, "invalid rate"
    end
  end

  test "non-numeric rate returns bad_gateway" do
    mock_parsed = {
      'rates' => [
        { 'period' => @period, 'hotel' => @hotel, 'room' => @room, 'rate' => 'N/A' }
      ]
    }
    mock_response = OpenStruct.new(success?: true, parsed_response: mock_parsed)

    RateApiClient.stub(:get_rate, mock_response) do
      service = Api::V1::PricingService.new(period: @period, hotel: @hotel, room: @room)
      service.run

      assert_not service.valid?
      assert_equal :bad_gateway, service.error_status
      assert_includes service.errors.first, "invalid rate"
    end
  end

  test "API error returns bad_gateway" do
    mock_response = OpenStruct.new(success?: false, parsed_response: { 'error' => 'Something went wrong' })

    RateApiClient.stub(:get_rate, mock_response) do
      service = Api::V1::PricingService.new(period: @period, hotel: @hotel, room: @room)
      service.run

      assert_not service.valid?
      assert_equal :bad_gateway, service.error_status
      assert_includes service.errors.first, "Something went wrong"
    end
  end

  test "empty rates array returns bad_gateway" do
    mock_parsed = { 'rates' => [] }
    mock_response = OpenStruct.new(success?: true, parsed_response: mock_parsed)

    RateApiClient.stub(:get_rate, mock_response) do
      service = Api::V1::PricingService.new(period: @period, hotel: @hotel, room: @room)
      service.run

      assert_not service.valid?
      assert_equal :bad_gateway, service.error_status
      assert_includes service.errors.first, "no rates"
    end
  end

  test "nil rates returns bad_gateway" do
    mock_parsed = { 'rates' => nil }
    mock_response = OpenStruct.new(success?: true, parsed_response: mock_parsed)

    RateApiClient.stub(:get_rate, mock_response) do
      service = Api::V1::PricingService.new(period: @period, hotel: @hotel, room: @room)
      service.run

      assert_not service.valid?
      assert_equal :bad_gateway, service.error_status
    end
  end

  test "rate entry missing rate key returns bad_gateway" do
    mock_parsed = {
      'rates' => [
        { 'period' => @period, 'hotel' => @hotel, 'room' => @room }
      ]
    }
    mock_response = OpenStruct.new(success?: true, parsed_response: mock_parsed)

    RateApiClient.stub(:get_rate, mock_response) do
      service = Api::V1::PricingService.new(period: @period, hotel: @hotel, room: @room)
      service.run

      assert_not service.valid?
      assert_equal :bad_gateway, service.error_status
      assert_includes service.errors.first, "invalid rate"
    end
  end

  test "matching combo not found returns bad_gateway" do
    mock_parsed = {
      'rates' => [
        { 'period' => 'Winter', 'hotel' => 'GitawayHotel', 'room' => 'RestfulKing', 'rate' => 9000 }
      ]
    }
    mock_response = OpenStruct.new(success?: true, parsed_response: mock_parsed)

    RateApiClient.stub(:get_rate, mock_response) do
      service = Api::V1::PricingService.new(period: @period, hotel: @hotel, room: @room)
      service.run

      assert_not service.valid?
      assert_equal :bad_gateway, service.error_status
    end
  end

  test "timeout returns gateway_timeout" do
    RateApiClient.stub(:get_rate, ->(*) { raise Net::ReadTimeout, "execution expired" }) do
      service = Api::V1::PricingService.new(period: @period, hotel: @hotel, room: @room)
      service.run

      assert_not service.valid?
      assert_equal :gateway_timeout, service.error_status
      assert_includes service.errors.first, "timed out"
    end
  end

  test "quota exceeded returns service_unavailable without calling API" do
    key = PricingUpstreamBudget.key_for_today
    Rails.cache.write(key, PricingUpstreamBudget::LIMIT, expires_in: 24.hours)

    RateApiClient.stub(:get_rate, ->(*) { raise "API should not be called" }) do
      service = Api::V1::PricingService.new(period: @period, hotel: @hotel, room: @room)
      service.run

      assert_not service.valid?
      assert_equal :service_unavailable, service.error_status
      assert_includes service.errors.first, "quota exhausted"
    end
  end

  test "unexpected error returns service_unavailable" do
    RateApiClient.stub(:get_rate, ->(*) { raise StandardError, "connection reset" }) do
      service = Api::V1::PricingService.new(period: @period, hotel: @hotel, room: @room)
      service.run

      assert_not service.valid?
      assert_equal :service_unavailable, service.error_status
      assert_includes service.errors.first, "unavailable"
    end
  end
end

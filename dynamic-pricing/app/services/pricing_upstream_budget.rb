module PricingUpstreamBudget
  LIMIT = 950 # keep headroom under 1000/day

  class QuotaExceeded < StandardError; end

  def self.key_for_today
    "pricing:upstream_calls:#{Date.current.iso8601}"
  end

  # read-only check; raises if already over limit
  def self.check_quota!
    current = Rails.cache.read(key_for_today) || 0
    if current >= LIMIT
      raise QuotaExceeded, "Upstream quota budget exhausted (#{current}/#{LIMIT})"
    end
  end

  # increments daily counter; raises if over limit
  def self.consume!(amount: 1)
    key = key_for_today

    new_val = Rails.cache.increment(key, amount, expires_in: 24.hours)

    # Some cache stores return nil for increment (e.g., NullStore/FileStore)
    if new_val.nil?
      raise QuotaExceeded, "Cache store does not support atomic increment (#{Rails.cache.class.name})"
    end

    if new_val > LIMIT
      Rails.cache.decrement(key, amount) rescue nil
      raise QuotaExceeded, "Upstream quota budget exhausted (#{new_val}/#{LIMIT})"
    end

    new_val
  end
end
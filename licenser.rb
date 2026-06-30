require 'date'

class Licenser
  LIMIT_REQUESTS_PER_SECOND = 1
  LIMIT_REQUEST_PER_DAY = 100
  POLL_SLEEP_SECONDS = 0.05
  REQUEST_COUNT_FILE = 'request_count.json'

  def initialize(api_keys)
    @api_keys = api_keys
    load_request_count
    @next_available_at = {}
    @mutex = Mutex.new
  end

  # Waits until one API key can be used, or returns nil if all keys hit the daily limit.
  def get_next_usable_api_key
    loop do
      result = try_mark_next_usable_api_key
      return result[:api_key] unless result[:api_key].nil?
      return nil if result[:api_keys].empty?

      sleep_until_next_api_key(result[:api_keys])
    end
  end

  # Waits until one API key can be used, preferring the available key with the lowest daily count.
  def get_next_balanced_api_key
    loop do
      result = try_mark_next_balanced_api_key
      return result[:api_key] unless result[:api_key].nil?
      return nil if result[:api_keys].empty?

      sleep_until_next_api_key(result[:api_keys])
    end
  end

  def persist_request_count
    begin
      request_count = @mutex.synchronize { @request_count }
      File.write(REQUEST_COUNT_FILE, JSON.pretty_generate(request_count))
    rescue => exception
      abort "An error persisting the request count: #{exception.message}"
    end
  end

  def get_quota_available_api_keys
    @mutex.synchronize do
      @today = get_today
      @api_keys.select do |api_key|
        get_request_count(api_key) < LIMIT_REQUEST_PER_DAY
      end
    end
  end

  def mark_api_key_as_used(api_key)
    @mutex.synchronize do
      @today = get_today
      if get_request_count(api_key) >= LIMIT_REQUEST_PER_DAY
        return false
      end

      increase_request_count(api_key)
      @next_available_at[api_key] = Time.now + request_window_seconds
      true
    end
  end

  def wait_until_api_key_available(api_key)
    loop do
      sleep_seconds = @mutex.synchronize do
        get_next_available_at(api_key) - Time.now
      end

      break unless sleep_seconds.positive?

      sleep [sleep_seconds, POLL_SLEEP_SECONDS].min
    end
  end

  private

  def try_mark_next_usable_api_key
    @mutex.synchronize do
      @today = get_today
      api_keys = get_quota_available_api_keys_without_lock
      api_key = api_keys.find { |key| is_api_key_available?(key) }
      mark_api_key_as_used_without_lock(api_key) unless api_key.nil?

      { api_key: api_key, api_keys: api_keys }
    end
  end

  def try_mark_next_balanced_api_key
    @mutex.synchronize do
      @today = get_today
      api_keys = get_quota_available_api_keys_without_lock
      api_key = api_keys
        .select { |key| is_api_key_available?(key) }
        .min_by { |key| get_request_count(key) }
      mark_api_key_as_used_without_lock(api_key) unless api_key.nil?

      { api_key: api_key, api_keys: api_keys }
    end
  end

  def load_request_count
    begin
      unless File.exist?(REQUEST_COUNT_FILE)
        @request_count = {}
        persist_request_count
        return
      end

      @request_count = JSON.parse(File.read(REQUEST_COUNT_FILE))
    rescue => exception
      abort "An error loading the request count: #{exception.message}"
    end
  end

  def is_api_key_available?(api_key)
    get_next_available_at(api_key) <= Time.now
  end

  def get_quota_available_api_keys_without_lock
    @api_keys.select do |api_key|
      get_request_count(api_key) < LIMIT_REQUEST_PER_DAY
    end
  end

  def mark_api_key_as_used_without_lock(api_key)
    increase_request_count(api_key)
    @next_available_at[api_key] = Time.now + request_window_seconds
  end

  def sleep_until_next_api_key(api_keys)
    next_available_at = @mutex.synchronize do
      api_keys.map { |api_key| get_next_available_at(api_key) }.min
    end
    sleep_seconds = [next_available_at - Time.now, POLL_SLEEP_SECONDS].min
    sleep sleep_seconds if sleep_seconds.positive?
  end

  def get_next_available_at(api_key)
    @next_available_at[api_key] || Time.at(0)
  end

  def get_request_count(api_key)
    @request_count[api_key] ||= {}
    @request_count[api_key][@today] ||= 0
  end

  def increase_request_count(api_key)
    @request_count[api_key][@today] += 1
  end

  def get_today
    Time.now.utc.to_date.strftime('%Y-%m-%d')
  end

  def request_window_seconds
    1.0 / LIMIT_REQUESTS_PER_SECOND
  end
end

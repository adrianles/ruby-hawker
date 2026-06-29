class Licenser
  LIMIT_REQUESTS_PER_SECOND = 1
  LIMIT_REQUEST_PER_DAY = 100
  POLL_SLEEP_SECONDS = 0.05
  REQUEST_COUNT_FILE = 'request_count.json'

  def initialize(api_keys)
    @api_keys = api_keys
    load_request_count
    @next_available_at = {}
  end

  # Waits until one API key can be used, or returns nil if all keys hit the daily limit.
  def get_next_usable_api_key
    loop do
      @today = get_today
      api_keys = get_quota_available_api_keys
      if api_keys.empty?
        return nil
      end

      api_key = api_keys.find { |key| is_api_key_available?(key) }
      unless api_key.nil?
        mark_api_key_as_used(api_key)
        return api_key
      end

      sleep_until_next_api_key(api_keys)
    end
  end

  def persist_request_count
    begin
      File.write(REQUEST_COUNT_FILE, JSON.pretty_generate(@request_count))
    rescue => exception
      abort "An error persisting the request count: #{exception.message}"
    end
  end

  private

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

  def mark_api_key_as_used(api_key)
    increase_request_count(api_key)
    @next_available_at[api_key] = Time.now + request_window_seconds
  end

  def get_quota_available_api_keys
    @api_keys.select do |api_key|
      get_request_count(api_key) < LIMIT_REQUEST_PER_DAY
    end
  end

  def is_api_key_available?(api_key)
    get_next_available_at(api_key) <= Time.now
  end

  def sleep_until_next_api_key(api_keys)
    next_available_at = api_keys.map { |api_key| get_next_available_at(api_key) }.min
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

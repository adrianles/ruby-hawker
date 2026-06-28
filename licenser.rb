class Licenser
  LIMIT_REQUESTS_PER_SECOND = 1
  LIMIT_REQUEST_PER_DAY = 100
  REQUEST_COUNT_FILE = 'request_count.json'

  def initialize(api_keys)
    @api_keys = api_keys
    load_request_count
    @last_usable_api_keys = {}
  end

  # Returns nil or a pair of [api_key, timeout_seconds] for the next request.
  def get_now_useable_api_key
    api_key = get_usable_api_key
    if api_key.nil?
      return [nil, get_default_timeout]
    end

    increase_request_count(api_key)
    last_usable_key_count = @last_usable_api_keys.length
    mark_api_key_as_used(api_key)
    [api_key, get_fast_timeout(last_usable_key_count)]
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

  def get_usable_api_key
    if @last_usable_api_keys.empty?
      load_usable_api_keys
    end

    get_last_usable_api_keys.first
  end

  def get_last_usable_api_keys
    @last_usable_api_keys.select { |_, value| value == true }.keys
  end

  def mark_api_key_as_used(api_key)
    @last_usable_api_keys[api_key] = false
    if get_last_usable_api_keys.empty?
      @last_usable_api_keys = {}
    end
  end

  def load_usable_api_keys
    @today = get_today
    @last_usable_api_keys = {}
    @api_keys.select do |api_key|
      count = get_request_count(api_key)
      if count < LIMIT_REQUEST_PER_DAY
        @last_usable_api_keys[api_key] = true
      end
    end
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

  def round_up_to_first_decimal(number)
    (number * 10).ceil / 10.0
  end

  def get_default_timeout
    round_up_to_first_decimal(1.0 / LIMIT_REQUESTS_PER_SECOND)
  end

  def get_fast_timeout(usable_api_keys_count)
    round_up_to_first_decimal((1.0 / LIMIT_REQUESTS_PER_SECOND) / usable_api_keys_count)
  end
end

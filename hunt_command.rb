require 'thor'
require 'httparty'
require 'json'
require 'date'
require 'csv'

require_relative 'config_definition'
require_relative 'applicant'
require_relative 'moderator'
require_relative 'smith'
require_relative 'licenser'
require_relative 'station'

class HuntCommand < Thor

  OUTPUT_DATETIME_FORMAT = '%Y-%m-%dT%H:%M:%S'
  OUTPUT_DATE_FORMAT = '%Y-%m-%d'
  HUNT_TIMEOUT = 1 # seconds
  HUNT_PAIRING_GAP_DAYS = 7

  desc 'hunt', 'The hawker hunts for prays in different dates'
  def hunt
    verbose = false
    timestamp = Time.now

    load_config
    search_config = @config[ConfigDefinition::SEARCH]

    if @config[ConfigDefinition::API_KEYS].length == 0
      abort "No API keys configured. Please add at least one API key in the search_config.json file."
    end
    licenser = Licenser.new(@config[ConfigDefinition::API_KEYS])

    search_start_date = get_outbound_date(search_config[ConfigDefinition::SEARCH_OUTBOUND_DATE])
    is_return = search_config[ConfigDefinition::SEARCH_IS_RETURN]
    search_end_date = get_hunt_end_date(search_config[ConfigDefinition::SEARCH_INBOUND_DATE], is_return)
    if search_end_date < search_start_date
      abort "Invalid hunt date range: no searchable dates available with a #{HUNT_PAIRING_GAP_DAYS}-day return pairing gap."
    end

    request_count = 0
    min_prices = {}

    search_start_date.upto(search_end_date) do |search_date|
      api_key, timeout = licenser.get_now_useable_api_key
      if api_key.nil?
        puts "No usable API keys available. You have reached the daily limit for the provided API keys."
        break
      end

      paired_return_date = is_return ? search_date + HUNT_PAIRING_GAP_DAYS : nil
      file_suffix = "hunt-#{search_date.strftime(OUTPUT_DATE_FORMAT)}"
      formatted_data = _capture(timestamp, api_key, search_date, is_return, paired_return_date, false, verbose, file_suffix)
      overview = formatted_data[:overview]
      request_count += 1
      min_price = overview.nil? ? nil : overview[:outbound][:price]
      min_prices[search_date] = min_price
      puts "[#{request_count}] #{search_date.strftime('%Y-%m-%d')}: #{min_price.nil? ? '-' : min_price}€"
      sleep timeout
    end

    licenser.persist_request_count
    puts "request count: #{request_count}"
    write_hunt_min_price_csv(timestamp, get_min_price_csv(get_min_prices_matrix(
      "#{search_config[ConfigDefinition::SEARCH_ORIGIN][ConfigDefinition::SEARCH_STATION_CODE]}-#{search_config[ConfigDefinition::SEARCH_DESTINATION][ConfigDefinition::SEARCH_STATION_CODE]}",
      min_prices,
    )))
  end

  desc 'capture', 'The hawker captures a pray in specific dates'
  def capture
    verbose = true
    timestamp = Time.now

    load_config
    search_config = @config[ConfigDefinition::SEARCH]

    if @config[ConfigDefinition::API_KEYS].length == 0
      abort "No API keys configured. Please add at least one API key in the search_config.json file."
    end
    licenser = Licenser.new(@config[ConfigDefinition::API_KEYS])
    api_key, _ = licenser.get_now_useable_api_key
    if api_key.nil?
      abort "No usable API keys available. You have reached the daily limit for the provided API keys."
    end

    outbound_date = get_outbound_date(search_config[ConfigDefinition::SEARCH_OUTBOUND_DATE])

    is_return = search_config[ConfigDefinition::SEARCH_IS_RETURN]
    inbound_date = nil
    if is_return
      inbound_date = get_inbound_date(search_config[ConfigDefinition::SEARCH_INBOUND_DATE])
    end

    file_suffix = "capture-#{outbound_date.strftime(OUTPUT_DATE_FORMAT)}"
    if is_return
      file_suffix = "#{file_suffix}-#{inbound_date.strftime(OUTPUT_DATE_FORMAT)}"
    end

    _capture(timestamp, api_key, outbound_date, is_return, inbound_date, false, verbose, file_suffix)
    licenser.persist_request_count
  end

  private

  def _capture(
    timestamp,
    api_key,
    outbound_date,
    is_return = false,
    inbound_date = nil,
    skip_request = false,
    verbose = false,
    file_suffix
  )
    @_verbose = verbose

    puts_if_verbose 'Preparing the search...'

    search_config = @config[ConfigDefinition::SEARCH]

    origin = search_config[ConfigDefinition::SEARCH_ORIGIN]
    origin_code = origin[ConfigDefinition::SEARCH_STATION_CODE]
    destination = search_config[ConfigDefinition::SEARCH_DESTINATION]
    destination_code = destination[ConfigDefinition::SEARCH_STATION_CODE]

    puts_if_verbose "Searching from #{outbound_date} [#{origin_code}->#{destination_code}]"
    if is_return
      puts_if_verbose 'Searching for return tickets'
      puts_if_verbose "Searching until #{inbound_date} [#{destination_code}->#{origin_code}]"
    else
      puts_if_verbose 'Searching for single tickets'
    end

    currency = 'EUR'

    if !skip_request
      applicant = Applicant.new(api_key, currency)
      json_data = applicant.query(origin, destination, outbound_date, is_return, inbound_date)
      write_raw_data(timestamp, json_data, file_suffix)
    else
      # file = 'data/example/mad-ams-single.json'
      file = 'data/example/par-tyo-return.json'
      json_data = File.read(file)
      puts_if_verbose 'Skipping request. Using file: ' + file
    end

    raw_data = JSON.parse(json_data, symbolize_names: false)

    filters = search_config['exclude']
    moderator = Moderator.new
    filtered_data = moderator.filter(raw_data, filters)

    smith = Smith.new
    formatted_data = smith.format({
        timestamp: timestamp.strftime(OUTPUT_DATETIME_FORMAT),
        outbound_date: outbound_date.strftime(OUTPUT_DATE_FORMAT),
        inbound_date: is_return ? inbound_date.strftime(OUTPUT_DATE_FORMAT) : nil,
        origin: origin_code,
        destination: destination_code,
        is_return: is_return,
        currency: currency,
        filters: filters,
      },
      filtered_data,
    )
    write_output_data(timestamp, formatted_data, file_suffix)

    puts_if_verbose "Search completed"

    return formatted_data
  rescue => exception
    puts_if_verbose "An error occurred: #{exception.message} \n#{exception.backtrace.join("\n")}"
  end

  def puts_if_verbose(message)
    puts message if @_verbose
  end

  def load_config
    begin
      @config = JSON.parse(File.read('search_config.json'))
      resolve_search_stations
    rescue => exception
      abort "An error loading the search config: #{exception.message}"
    end
  end

  def resolve_search_stations
    search_config = @config[ConfigDefinition::SEARCH]
    search_config[ConfigDefinition::SEARCH_ORIGIN] = Station.from_config(search_config[ConfigDefinition::SEARCH_ORIGIN])
    search_config[ConfigDefinition::SEARCH_DESTINATION] = Station.from_config(search_config[ConfigDefinition::SEARCH_DESTINATION])
  end

  def get_outbound_date(config_outbound_date)
    begin
      if config_outbound_date == nil
        return Date.today
      end

      [Date.today, Date.strptime(config_outbound_date, '%Y-%m-%d')].max
    rescue => exception
      abort "Invalid outbound date: #{exception.message}"
    end
  end

  def get_inbound_date(config_inbound_date)
    latestDate = Date.today >> 11  # Add 11 months
    begin
      if config_inbound_date == nil
        return latestDate
      end

      [latestDate, Date.strptime(config_inbound_date, '%Y-%m-%d')].min
    rescue => exception
      abort "Invalid inbound date: #{exception.message}"
    end
  end

  def get_hunt_end_date(config_inbound_date, is_return)
    end_date = get_inbound_date(config_inbound_date)
    if is_return
      latest_paired_return_date = get_inbound_date(nil)
      end_date = [end_date, latest_paired_return_date - HUNT_PAIRING_GAP_DAYS].min
    end

    end_date
  end

  def write_raw_data(timestamp, json_raw_data, file_suffix)
    file_path = "data/response/#{get_output_file_name(timestamp, file_suffix)}.json"
    File.write(file_path, json_raw_data)
    puts_if_verbose "Response written to #{file_path}"
  end

  def write_output_data(timestamp, output_data, file_suffix)
    file_path = "data/output/#{get_output_file_name(timestamp, file_suffix)}.json"
    File.write(file_path, output_data.to_json)
    puts_if_verbose "Output written to #{file_path}"
  end

  def get_output_file_name(timestamp, file_suffix)
    "#{timestamp.strftime(OUTPUT_DATETIME_FORMAT)}-#{file_suffix}"
  end

  def write_hunt_min_price_csv(timestamp, csv_min_price_data)
    file_path = "data/output/#{get_output_file_name(timestamp, 'summary')}.csv"
    File.write(file_path, csv_min_price_data)
    puts_if_verbose "min price CSV data written to #{file_path}"
  end

  def get_min_prices_matrix(route, min_prices)
    dates = min_prices.keys.sort

    matrix = dates.map do |date|
      [date.strftime(OUTPUT_DATE_FORMAT), min_prices[date]]
    end

    [['date', route]] + matrix
  end

  def get_min_price_csv(min_prices_matrix)
    csv_string = CSV.generate do |csv|
      min_prices_matrix.each { |row| csv << row }
    end

    return csv_string
  end
end

HuntCommand.start(ARGV)

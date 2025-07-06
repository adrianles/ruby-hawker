require 'thor'
require 'httparty'
require 'json'
require 'date'
require 'csv'

require_relative 'config_definition'
require_relative 'applicant'
require_relative 'moderator'
require_relative 'smith'

class HuntCommand < Thor

  OUTPUT_DATETIME_FORMAT = '%Y-%m-%dT%H:%M:%S'
  OUTPUT_DATE_FORMAT = '%Y-%m-%d'
  HUNT_TIMEOUT = 0.6 # seconds

  desc 'hunt', 'The hawker hunts for prays in different dates'
  def hunt
    verbose = true

    load_config
    search_config = @config[ConfigDefinition::SEARCH]

    outbound_date = get_outbound_date(search_config[ConfigDefinition::SEARCH_OUTBOUND_DATE])
    inbound_date = get_inbound_date(search_config[ConfigDefinition::SEARCH_INBOUND_DATE])
    is_return = search_config[ConfigDefinition::SEARCH_IS_RETURN]

    request_count = 0
    o_min_prices = {}
    i_min_prices = {}

    outbound_date.upto(inbound_date) do |o_date|
      formatted_data = _capture(o_date, is_return, inbound_date, false, verbose)
      overview = formatted_data[:overview]
      request_count += 1
      min_price = overview.nil? ? nil : overview[:outbound][:price]
      o_min_prices[o_date] = min_price
      puts o_min_prices.inspect
      puts "[#{request_count}] out #{o_date.strftime('%Y-%m-%d')}: outbound flight price = #{min_price.nil? ? '-' : min_price}€" if verbose
      sleep HUNT_TIMEOUT
    end

    if is_return
      outbound_date.upto(inbound_date) do |i_date|
        formatted_data = _capture(outbound_date, is_return, i_date, false, verbose)
        overview = formatted_data[:overview]
        request_count += 1
        min_price = overview.nil? ? nil : overview[:inbound][:price]
        i_min_prices[i_date] = min_price
        puts i_min_prices.inspect
        puts "[#{request_count}] in #{i_date.strftime('%Y-%m-%d')}: inbound flight price = #{min_price.nil? ? '-' : min_price}€" if verbose
        sleep HUNT_TIMEOUT
      end
    end

    puts "request count: #{request_count}"
    puts get_min_price_csv(get_min_prices_matrix(o_min_prices, i_min_prices))
  end

  desc 'capture', 'The hawker captures a pray in specific dates'
  def capture
    verbose = false

    load_config
    search_config = @config[ConfigDefinition::SEARCH]

    outbound_date = get_outbound_date(search_config[ConfigDefinition::SEARCH_OUTBOUND_DATE])

    is_return = search_config[ConfigDefinition::SEARCH_IS_RETURN]
    inbound_date = nil
    if is_return
      inbound_date = get_inbound_date(search_config[ConfigDefinition::SEARCH_INBOUND_DATE])
    end

    _capture(outbound_date, is_return, inbound_date, false, verbose)
  end

  private

  def _capture(
    outbound_date,
    is_return = false,
    inbound_date = nil,
    skip_request = false,
    verbose = false
  )
    @_verbose = verbose

    puts_if_verbose 'Preparing the search...'

    search_config = @config[ConfigDefinition::SEARCH]

    origin = search_config[ConfigDefinition::SEARCH_ORIGIN]
    destination = search_config[ConfigDefinition::SEARCH_DESTINATION]

    puts_if_verbose "Searching from #{outbound_date} [#{origin}->#{destination}]"
    if is_return
      puts_if_verbose 'Searching for return tickets'
      puts_if_verbose "Searching until #{inbound_date} [#{destination}->#{origin}]"
    else
      puts_if_verbose 'Searching for single tickets'
    end

    currency = 'EUR'

    timestamp = Time.now

    if !skip_request
      applicant = Applicant.new(@config[ConfigDefinition::API_KEY], currency)
      json_data = applicant.query(origin, destination, outbound_date, is_return, inbound_date)
      write_raw_data(timestamp, json_data)
    else
      # file = 'data/example/mad-ams-single.json'
      file = 'data/example/mad-ams-return.json'
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
        origin: origin,
        destination: destination,
        is_return: is_return,
        currency: currency,
        filters: filters,
      },
      filtered_data,
    )
    write_output_data(timestamp, formatted_data)

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
    rescue => exception
      abort "An error loading the search config: #{exception.message}"
    end
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

  def write_raw_data(timestamp, json_raw_data)
    file_path = "data/response/#{timestamp.strftime('%Y-%m-%dT%H:%M:%S')}.json"
    File.write(file_path, json_raw_data)
    puts_if_verbose "Response written to #{file_path}"
  end

  def write_output_data(timestamp, output_data)
    file_path = "data/output/#{timestamp.strftime('%Y-%m-%dT%H:%M:%S')}.json"
    File.write(file_path, output_data.to_json)
    puts_if_verbose "Output written to #{file_path}"
  end

  def get_min_prices_matrix(o_min_prices, i_min_prices)
    dates = (o_min_prices.keys + i_min_prices.keys).uniq.sort

    dates.map do |date|
      [date, o_min_prices[date], i_min_prices[date]]
    end
  end

  def get_min_price_csv(min_prices_matrix)
    csv_string = CSV.generate do |csv|
      min_prices_matrix.each { |row| csv << row }
    end

    return csv_string
  end
end

HuntCommand.start(ARGV)

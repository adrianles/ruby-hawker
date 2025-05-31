require 'thor'
require 'httparty'
require 'json'
require 'date'

require_relative 'config_definition'
require_relative 'applicant'
require_relative 'smith'

class HuntCommand < Thor
  desc 'hunt', 'The hawker hunts its prey'

  OUTPUT_DATETIME_FORMAT = '%Y-%m-%dT%H:%M:%S'

  def hunt
    puts 'Preparing the search...'

    skip_request = false

    load_config
    search_config = @config[ConfigDefinition::SEARCH]

    origin = search_config[ConfigDefinition::SEARCH_ORIGIN]
    destination = search_config[ConfigDefinition::SEARCH_DESTINATION]

    outbound_date = get_outbound_date(search_config[ConfigDefinition::SEARCH_OUTBOUND_DATE])
    puts "Searching from #{outbound_date}"

    is_return = search_config[ConfigDefinition::SEARCH_IS_RETURN]
    inbound_date = nil
    if is_return
      puts 'Searching for return tickets'
      inbound_date = get_inbound_date(search_config[ConfigDefinition::SEARCH_INBOUND_DATE])
      puts "Searching until #{inbound_date}"
    else
      puts 'Searching for single tickets'
    end

    currency = 'EUR'

    timestamp = Time.now

    if !skip_request
      applicant = Applicant.new(@config[ConfigDefinition::API_KEY], currency)
      raw_data = applicant.query(origin, destination, outbound_date, is_return, inbound_date)
      write_raw_data(timestamp, raw_data)
    else
      raw_data = File.read('data/response/2025-05-30T13:59:05.json')
    end

    smith = Smith.new
    formatted_data = smith.format({
        'timestamp': timestamp.strftime(OUTPUT_DATETIME_FORMAT),
        'outboundDate': outbound_date.strftime(OUTPUT_DATETIME_FORMAT),
        'inboundDate': is_return ? inbound_date.strftime(OUTPUT_DATETIME_FORMAT) : nil,
        'origin': origin,
        'destination': destination,
        'currency': currency,
      },
      raw_data,
    )
    write_output_data(timestamp, formatted_data)

    puts "Search completed"
  rescue => exception
    puts "An error occurred: #{exception.message} \n#{exception.backtrace.join("\n")}"
  end

  private

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
    puts "Response written to #{file_path}"
  end

  def write_output_data(timestamp, output_data)
    file_path = "data/output/#{timestamp.strftime('%Y-%m-%dT%H:%M:%S')}.json"
    File.write(file_path, output_data.to_json)
    puts "Output written to #{file_path}"
  end
end

HuntCommand.start(ARGV)

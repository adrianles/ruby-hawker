require 'thor'
require 'httparty'
require 'json'
require 'date'
require_relative 'config_definition'

class HuntCommand < Thor
  desc 'hunt', 'The hawker hunts its prey'

  API_DATE_FORMAT = '%Y-%m-%d';

  def hunt
    puts 'Preparing the search...'

    load_config

    load_outbound_date
    puts "Searching from #{@outbound_date}"

    if @config[ConfigDefinition::SEARCH][ConfigDefinition::SEARCH_IS_RETURN]
      puts 'Searching for return tickets'
      load_inbound_date
      puts "Searching until #{@inbound_date}"
    else
      puts 'Searching for single tickets'
    end

    request_data

    handle_response

    format_data

    puts "Search completed"
  rescue => exception
    puts "An error occurred: #{exception.message}"
  end

  private

  def load_config
    begin
      @config = JSON.parse(File.read('search_config.json'))
    rescue => exception
      abort "An error loading the search config: #{exception.message}"
    end
  end

  def load_outbound_date
    begin
      configOutboundDate = @config[ConfigDefinition::SEARCH][ConfigDefinition::SEARCH_OUTBOUND_DATE]
      if configOutboundDate == nil
        @outbound_date = Date.today
      else
        @outbound_date = [Date.today, Date.strptime(configOutboundDate, '%Y-%m-%d')].max
      end
    rescue => exception
      abort "Invalid outbound date: #{exception.message}"
    end
  end

  def load_inbound_date
    latestDate = Date.today >> 11  # Add 11 months
    configInboundDate = @config[ConfigDefinition::SEARCH][ConfigDefinition::SEARCH_INBOUND_DATE]
    begin
      if configInboundDate == nil
        @inbound_date = latestDate
      else
        @inbound_date = [latestDate, Date.strptime(configInboundDate, '%Y-%m-%d')].min
      end
    rescue => exception
      abort "Invalid inbound date: #{exception.message}"
    end
  end

  def request_data
    @timestamp = Time.now
    begin
      @response = HTTParty.post(
        # @see https://developer.airfranceklm.com/products/api/offers/api-reference/
        'https://api.airfranceklm.com/opendata/offers/v1/available-offers',
        headers: get_request_headers,
        body: get_request_body.to_json
      )
    rescue => exception
      abort "An error during the request: #{exception.message}"
    end
  end

  def get_request_headers
    {
      'AFKL-TRAVEL-Host' => 'KL',
      'API-Key' => @config[ConfigDefinition::API_KEY],
      'Accept' => 'application/hal+json',
      'Content-Type' => 'application/hal+json'
    }
  end

  def get_request_body
    search_config = @config[ConfigDefinition::SEARCH]

    requested_conections = [
      create_flight_connection(
        @outbound_date.strftime(API_DATE_FORMAT),
        search_config[ConfigDefinition::SEARCH_ORIGIN],
        search_config[ConfigDefinition::SEARCH_DESTINATION]
      )
    ]
    if search_config[ConfigDefinition::SEARCH_IS_RETURN]
      create_flight_connection(
        @inbound_date.strftime(API_DATE_FORMAT),
        search_config[ConfigDefinition::SEARCH_DESTINATION],
        search_config[ConfigDefinition::SEARCH_ORIGIN]
      )
    end

    {
      'commercialCabins': ['ALL'],
      'bookingFlow': 'LEISURE',
      'passengers': [{ 'id': 1, 'type': 'ADT' }],
      'requestedConnections': requested_conections,
      'currency': 'EUR'
    }
  end

  def create_flight_connection(date, origin, destination)
    {
      'departureDate': date,
      'origin': {
        'code': origin,
        'type': 'STOPOVER'
      },
      'destination': {
        'code': destination,
        'type': 'STOPOVER'
      }
    }
  end

  def handle_response
    if @response.code == 200
      file_path = "data/response/#{@timestamp}.json"
      File.write(file_path, @response.body)
      puts "Response written to #{file_path}"
    else
      puts "Error: Response failed with code #{@response.code}"
      abort @response.body
    end
  end

  def format_data
    # data = JSON.parse(response.body)
  end
end

HuntCommand.start(ARGV)

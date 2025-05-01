require 'thor'
require 'httparty'
require 'json'
require 'date'
require_relative 'config_definition'

class HuntCommand < Thor
  desc 'hunt', 'The hawker hunts its prey'

  def hunt
    puts 'Preparing the search...'

    load_config

    load_outbound_date
    puts "Searching from #{@outboundDate}"

    if @config[ConfigDefinition::SEARCH][ConfigDefinition::SEARCH_IS_RETURN]
      puts 'Searching for return tickets'
      load_inbound_date
      puts "Searching until #{@inboundDate}"
    else
      puts 'Searching for single tickets'
    end

    # request_data

    # handle_response

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
        @outboundDate = Date.today
      else
        @outboundDate = [Date.today, Date.strptime(configOutboundDate, '%Y-%m-%d')].max
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
        @inboundDate = latestDate
      else
        @inboundDate = [latestDate, Date.strptime(configInboundDate, '%Y-%m-%d')].min
      end
    rescue => exception
      abort "Invalid inbound date: #{exception.message}"
    end
  end

  def request_data
    @response = HTTParty.post(
      # @see https://developer.airfranceklm.com/products/api/offers/api-reference/
      'https://api.airfranceklm.com/opendata/offers/v1/available-offers',
      headers: get_request_headers,
      body: get_request_body.to_json
    )
  end

  def get_request_headers
    return {
      # 'AFKL-TRAVEL-Host' => 'KL or AF',
      'API-Key' => @config[ConfigDefinition::API_KEY],
      'Accept' => 'application/hal+json',
      'Content-Type' => 'application/hal+json'
    }
  end

  def get_request_body
    search_config = @config[ConfigDefinition::SEARCH]

    requested_conections = [
      create_flight_connection(
        @outbound_date,
        @search_config[ConfigDefinition::SEARCH_ORIGIN],
        @search_config[ConfigDefinition::SEARCH_DESTINATION]
      )
    ]
    if search_config[ConfigDefinition::SEARCH_IS_RETURN]
      create_flight_connection(
        @inbound_date,
        @search_config[ConfigDefinition::SEARCH_DESTINATION],
        @search_config[ConfigDefinition::SEARCH_ORIGIN]
      )
    end

    return {
      commercialCabins: ['ALL'],
      bookingFlow: 'LEISURE',
      passengers: [{ id: 1, type: 'ADT' }],
      requestedConnections: requested_conections
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
    if response.code == 200
      data = JSON.parse(response.body)

      # Example calculation: sum "value" fields
      total = data.map { |item| item["value"] }.sum

      File.write("output.txt", "Total value: #{total}")
      puts "Done! Result written to output.txt"
    else
      puts "Error: Failed to fetch data (#{response.code})"
    end
  end
end

HuntCommand.start(ARGV)

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
      file_path = "data/response/#{@timestamp.strftime('%Y-%m-%dT%H:%M:%S')}.json"
      File.write(file_path, @response.body)
      puts "Response written to #{file_path}"
    else
      puts "Error: Response failed with code #{@response.code}"
      abort @response.body
    end
  end

  def format_data
    response_data = JSON.parse(@response.body)

    intineraries = response_data['itineraries']
    if intineraries.nil? || intineraries.empty?
      abort "Unexpected JSON response: No itineraries found"
    end

    flights = []
    intineraries.each do |itinerary|
      flight = {
        'products': get_flight_products(itinerary),
        'connetions': get_flight_connetions(itinerary),
      }
      flight['overview'] = get_flight_overview(flight)
      flights << flight
    end

    search_config = @config[ConfigDefinition::SEARCH]
    output_datetime_format = '%Y-%m-%dT%H:%M:%S'
    output_data = {
      search: {
        'timestamp': @timestamp.strftime(output_datetime_format),
        'outboundDate': @outbound_date.strftime(output_datetime_format),
        'inboundDate': search_config[ConfigDefinition::SEARCH_IS_RETURN] ? @inbound_date.strftime(output_datetime_format) : nil,
        'origin': search_config[ConfigDefinition::SEARCH_ORIGIN],
        'destination': search_config[ConfigDefinition::SEARCH_DESTINATION],
        'currency': 'EUR',
      },
      results: flights
    }

    file_path = "data/output/#{@timestamp.strftime('%Y-%m-%dT%H:%M:%S')}.json"
    File.write(file_path, output_data.to_json)
    puts "Output written to #{file_path}"
  end

  def get_flight_products(itinerary)
    flightProducts = itinerary['flightProducts']
    if flightProducts.nil? || flightProducts.empty?
      abort "Unexpected JSON response: itineraries.flightProducts not found"
    end

    products = []
    flightProducts.each do |flightProduct|
      connections = flightProduct['connections']
      if connections.nil? || connections.empty?
        abort "Unexpected JSON response: itineraries.flightProducts.connections not found"
      end

      connections.each do |connection|
        products << {
          'class': connection['commercialCabin'],
          'price': connection['price']['totalPrice'],
        }
      end
    end

    products
  end

  def get_flight_connetions(itinerary)
    connections = itinerary['connections']
    if connections.nil? || connections.empty?
      abort "Unexpected JSON response: itineraries.connections not found"
    end

    flight_segments = []
    connections.each do |connection|
      segments = connection['segments']
      if segments.nil? || segments.empty?
        abort "Unexpected JSON response: itineraries.connections.segments not found"
      end

      segments.each do |segment|
        flight_segments << {
          'origin': segment['origin']['code'],
          'destination': segment['destination']['code'],
          'departureDatetime': segment['departureDateTime'],
          'arrivalDatetime': segment['arrivalDateTime'],
          'flightDuration': segment['flightDuration'],
          'flightId': "#{segment['marketingFlight']['carrier']['code']}#{segment['marketingFlight']['number']}"
        }
      end
    end

    flight_segments
  end

  def get_flight_overview(flight)
    economyPrice = flight[:products].find { |product| product[:class] == 'ECONOMY' }

    airports = []
    flight[:connetions].each do |connection|
      airports << connection[:origin]
    end
    airports << flight[:connetions].last[:destination]

    return {
      'departureTime': DateTime.parse(flight[:connetions].first[:departureDatetime]).strftime('%H:%M'),
      'arrivalTime': DateTime.parse(flight[:connetions].last[:arrivalDatetime]).strftime('%H:%M'),
      'price': economyPrice[:price],
      'airports': airports,
    }
  end
end

HuntCommand.start(ARGV)

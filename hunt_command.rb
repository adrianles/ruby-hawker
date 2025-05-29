require 'thor'
require 'httparty'
require 'json'
require 'date'

require_relative 'config_definition'
require_relative 'applicant'

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
      raw_data = File.read('data/response/2025-05-29T15:44:37.json')
    end

    formatted_data = format_data({
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

  def format_data(search_data, json_data)
    response_data = JSON.parse(json_data)

    intineraries = response_data['itineraries']
    if intineraries.nil? || intineraries.empty?
      abort "Unexpected JSON: No itineraries found"
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

    {search: search_data, results: flights}
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

  def write_raw_data(timestamp, raw_data)
    file_path = "data/response/#{timestamp.strftime('%Y-%m-%dT%H:%M:%S')}.json"
    File.write(file_path, raw_data.to_json)
    puts "Response written to #{file_path}"
  end

  def write_output_data(timestamp, output_data)
    file_path = "data/output/#{timestamp.strftime('%Y-%m-%dT%H:%M:%S')}.json"
    File.write(file_path, output_data.to_json)
    puts "Output written to #{file_path}"
  end
end

HuntCommand.start(ARGV)

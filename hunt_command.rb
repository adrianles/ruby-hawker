require 'thor'
require 'httparty'
require 'json'
require 'date'

class HuntCommand < Thor
  desc 'hunt', 'The hawker hunts its prey'

  # @see https://developer.airfranceklm.com/products/api/offers/api-reference/
  @url = 'https://api.airfranceklm.com/opendata/offers/v1/available-offers' # TODO: get from config

  def hunt
    puts 'Preparing the search...'

    load_config

    get_outbound_date
    puts "Searching from #{@outboundDate}"

    if @config['search']['return']
      puts 'Searching form return tickets'
      get_inbound_date
      puts "Searching until #{@inboundDate}"
    else
      puts 'Searching form single tickets'
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

  def get_outbound_date
    begin
      configOutboundDate = @config['search']['inboundDate']
      if configOutboundDate == nil
        @outboundDate = Date.today
      else
        @outboundDate = [Date.today, Date.strptime(configOutboundDate, '%Y-%m-%d')].max
      end
    rescue => exception
      abort "Invalid outbound date: #{exception.message}"
    end
  end

  def get_inbound_date
    latestDate = Date.today >> 11  # Add 11 months
    configInboundDate = @config['search']['inboundDate']
    begin
      if configInboundDate == nil
        @inboundDate = latestDate
      else
        @inboundDate = [latestDate, Date.strptime(configInboundDate, '%Y-%m-%d')].min
      end
    rescue => exception
      abort "Invalid outbound date: #{exception.message}"
    end
  end

  def request_data
    @response = HTTParty.post(
      url,
      :headers => { 
        # 'AFKL-TRAVEL-Host' => 'KL',
        'API-Key' => @config['api-key'],
        'Accept' => 'application/hal+json',
        'Content-Type' => 'application/hal+json'
      },
      :data => {
        'commercialCabins' => ['ALL'],
        'bookingFlow' => 'LEISURE',
        'passengers' => [{'id': 1, 'type': 'ADT'}],
        'requestedConnections': [
            create_flight_connection(@outboundDate, searchConfig['from'], searchConfig['to']),
            create_flight_connection(@inboundDate, searchConfig['to'], searchConfig['from']),
        ]
      }
    )
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

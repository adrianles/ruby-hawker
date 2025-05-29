class Applicant
  API_DATE_FORMAT = '%Y-%m-%d';

  def initialize(api_key, currency)
    @api_key = api_key
    @headers = {
      'AFKL-TRAVEL-Host' => 'KL',
      'API-Key' => @api_key,
      'Accept' => 'application/hal+json',
      'Content-Type' => 'application/hal+json'
    }

    @currency = currency
  end

  def query(origin, destination, outbound_date, is_return = false, inbound_date = nil)
    begin
      response = HTTParty.post(
        # @see https://developer.airfranceklm.com/products/api/offers/api-reference/
        'https://api.airfranceklm.com/opendata/offers/v1/available-offers',
        headers: @headers,
        body: get_request_body(
          origin,
          destination,
          outbound_date,
          is_return,
          inbound_date,
        ).to_json
      )

      handle_response(response)
    rescue => exception
      abort "An error during the request: #{exception.message}"
    end
  end

  private

  def get_request_body(origin, destination, outbound_date, is_return, inbound_date)
    requested_conections = [
      create_flight_connection(
        outbound_date.strftime(API_DATE_FORMAT),
        origin,
        destination,
      )
    ]
    if is_return
      create_flight_connection(
        inbound_date.strftime(API_DATE_FORMAT),
        destination,
        origin,
      )
    end

    {
      'commercialCabins': ['ALL'],
      'bookingFlow': 'LEISURE',
      'passengers': [{ 'id': 1, 'type': 'ADT' }],
      'requestedConnections': requested_conections,
      'currency': @currency
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

  def handle_response(response)
    if response.code != 200
      puts "Error: Request failed with code #{response.code}"
      abort response.body
    end

    response.body
  end
end
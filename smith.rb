require 'json'

class Smith
  TOTAL_PRICE_KEY = 'price'
  CURRENCY_KEY = 'currency'

  def format(search_data, json_data)
    response_data = JSON.parse(json_data)

    itineraries = response_data['itineraries']
    if itineraries.nil? || itineraries.empty?
      abort 'Unexpected JSON: No itineraries found'
    end

    bundles = []
    itineraries.each do |itinerary|
      bundle = get_bundle(itinerary)
      bundle['overview'] = get_product_overview(bundle)
      bundles.append(bundle)
    end

    { search: search_data, bundles: bundles }
  end

  def get_bundle(itinerary)
    flightProducts = itinerary['flightProducts']
    if flightProducts.nil? || flightProducts.empty?
      abort 'Unexpected JSON: itineraries.flightProducts not found'
    end

    connections = itinerary['connections']
    if connections.nil? || connections.empty?
      abort 'Unexpected JSON: itineraries[i].connections not found'
    end
    if connections.length > 2
      abort 'Unexpected JSON: more than 2 itineraries[i].connections found'
    end

    options_per_route = get_options_per_route(flightProducts)

    bundle = {}
    connections.each_index do |i|
      if options_per_route[i].nil? || options_per_route[i].empty?
        abort "Unexpected JSON: itineraries[i].flightProducts[j].connections[#{i}] does not match with itineraries[i].connections[#{i}]"
      end

      route = get_route(connections[i], options_per_route[i])
      case i
        when 0
          bundle['outbound'] = route
        when 1
          bundle['inbound'] = route
        else
          abort 'Unexpected JSON: more than 2 itineraries[i].connections found'
      end
    end

    bundle
  end

  def get_options_per_route(flightProducts)
    options_per_route = []
    flightProducts.each do |flightProduct|
      pf_connections = flightProduct['connections']
      if pf_connections.nil? || pf_connections.empty?
        abort 'Unexpected JSON: itineraries.flightProducts[i].connections not found'
      end

      pf_connections.each_index do |i|
        options_per_route[i] ||= []
        options_per_route[i].append({
          'class': {
            'code': pf_connections[i]['fareFamily']['code'],
            'hierarchy': pf_connections[i]['fareFamily']['hierarchy'],
            'name': pf_connections[i]['commercialCabin'],
          },
          'numberOfSeats': pf_connections[i]['numberOfSeatsAvailable'],
          'price': pf_connections[i]['price']['totalPrice'],
          'currency': pf_connections[i]['price']['currency'],
        })
      end
    end

    options_per_route
  end

  def get_route(connection, options)
    segments = connection['segments']
    if segments.nil? || segments.empty?
      abort 'Unexpected JSON: itineraries[i].connections[j].segments not found'
    end

    flights = []
    segments.each do |segment|
      flights << {
        'origin': segment['origin']['code'],
        'destination': segment['destination']['code'],
        'flightId': "#{segment['marketingFlight']['carrier']['code']}#{segment['marketingFlight']['number']}",
        'departureDatetime': segment['departureDateTime'],
        'arrivalDatetime': segment['arrivalDateTime'],
        'flightDuration': segment['flightDuration'],
        'transferTime': segment['transferTime'],
        'dateVariation': segment['dateVariation'],
      }
    end

    {
      'options': options,
      'dateVariation': connection['dateVariation'],
      'duration': connection['duration'],
      'flights': flights,
    }
  end

  def get_product_overview(product)
    # TODO
=begin
    economyPrice = product[:products].find { |product| product[:class] == 'ECONOMY' }

    airports = []
    product[:connetions].each do |connection|
      airports << connection[:origin]
    end
    airports << product[:connetions].last[:destination]

    return {
      'departureTime': DateTime.parse(product[:connetions].first[:departureDatetime]).strftime('%H:%M'),
      'arrivalTime': DateTime.parse(product[:connetions].last[:arrivalDatetime]).strftime('%H:%M'),
      'price': economyPrice[:price],
      'airports': airports,
    }
=end
    {}
  end
end

=begin
  option (product) = {
    fareFamily: {
      code: "BUSSTANDMH",
      hierarchy: 6000
    },
    class: "BUSINESS",
    numberOfSeatsAvailable: 2,
    price: price.totalPrice
  }

  route (connection) = {
    options: [option1, option2],
    flights: [flight1, flight2, flight3],
  }

  bundles (itinerary) = [
    [ruta_ida1, ruta_vuelta1, MIN_TOTAL_PRICE()],
    [ruta_ida1, ruta_vuelta2, MIN_TOTAL_PRICE()],
    [ruta_ida2, ruta_vuelta2, MIN_TOTAL_PRICE()],
  ]


  bundles = itinerary: [
    { 
      routes = connexion: [
        {
          options: [{
            fareFamily: {
              code: "LIGHT",
              hierarchy: 7500
            },
            class: "ECONOMY",
            numberOfSeatsAvailable: 5,
            price: price.totalPrice
            }, {
            fareFamily: {
              code: "BUSSTANDMH",
              hierarchy: 6000
            },
            class: "BUSINESS",
            numberOfSeatsAvailable: 2,
            price: price.totalPrice
            }
          ],
          flights = segment: [{
            origin: bio
            destination: ams
            departureDateTime: "2025-07-11T06:55:00",
            arrivalDateTime: "2025-07-11T09:35:00",
            transferTime: 80,
            dateVariation: 0,
            flightDuration: 160,
            }
          ],
        }, {
          options: [{
            fareFamily: {
              code: "LIGHT",
              hierarchy: 7500
            },
            class: "ECONOMY",
            numberOfSeatsAvailable: 5,
            price: price.totalPrice
            }, {
            fareFamily: {
              code: "BUSSTANDMH",
              hierarchy: 6000
            },
            class: "BUSINESS",
            numberOfSeatsAvailable: 2,
            price: price.totalPrice
            }
          ],
          flights = segment: [{
            origin: ams
            destination: mad
            departureDateTime: "2025-07-11T06:55:00",
            arrivalDateTime: "2025-07-11T09:35:00",
            transferTime: 80,
            dateVariation: 0,
            flightDuration: 160,
            }, {
            origin: mad
            destination: bio
            departureDateTime: "2025-07-11T06:55:00",
            arrivalDateTime: "2025-07-11T09:35:00",
            transferTime: 80,
            dateVariation: 0,
            flightDuration: 160,
            }
          ]
        },
    ] }
  ]

  itinerary: product = trip = bundle; ex: [bio-ams, ams-mad-bio]
    flights; ex: [bio-ams, ams-bio]
      segments; ex: [bio-ams]
                    [ams-mad, mad-bio]


=end

=begin
    example
      request: bio-ams & ams-bio
      response:

        flightProducts:
          price:
            totalPrice:
            currency:
          connections: [bio-ams, ams-bio]
            numberOfSeatsAvailable:
            fareFamily:
              code: string
              hierarchy: int
            commercialCabin:
            price:
              totalPrice:
              currency:
        connections: [bio-ams, ams-bio]
          dateVariation: 0 (+0 days)
          duration: 130 (minutes)
          segements: [bio-ams, ams-mad, mad-bio]
            origin:
            destination:
            marketingFlight:
            "departureDateTime": "2025-07-11T06:55:00",
            "arrivalDateTime": "2025-07-11T09:35:00",
            "transferTime": 80,
            "dateVariation": 0,
            "flightDuration": 160
=end

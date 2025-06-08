class Smith
  def format(search_data, response_data)
    @currency = search_data[:currency]

    itineraries = response_data['itineraries']
    if itineraries.nil? || itineraries.empty?
      abort 'Unexpected JSON: No itineraries found'
    end

    bundles = []
    itineraries.each do |itinerary|
      bundle = get_bundle(itinerary)
      bundle[:overview] = get_bundle_overview(bundle)
      bundles.append(bundle)
    end

    { search: search_data, bundles: bundles, overview: get_search_overview(bundles) }
  end

  private

  def get_bundle(itinerary)
    flightProducts = itinerary['flightProducts']
    if flightProducts.nil? || flightProducts.empty?
      abort 'Unexpected JSON: itineraries[i].flightProducts not found'
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
          bundle[:outbound] = route
        when 1
          bundle[:inbound] = route
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
          class: {
            code: pf_connections[i]['fareFamily']['code'],
            hierarchy: pf_connections[i]['fareFamily']['hierarchy'],
            name: pf_connections[i]['commercialCabin'],
          },
          number_of_seats: pf_connections[i]['numberOfSeatsAvailable'],
          price: pf_connections[i]['price']['totalPrice'],
          currency: pf_connections[i]['price']['currency'],
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
        origin: segment['origin']['code'],
        destination: segment['destination']['code'],
        flight_id: "#{segment['marketingFlight']['carrier']['code']}#{segment['marketingFlight']['number']}",
        departure_datetime: segment['departureDateTime'],
        arrival_datetime: segment['arrivalDateTime'],
        flight_duration: segment['flightDuration'],
        transfer_time: segment['transferTime'],
        date_variation: segment['dateVariation'],
      }
    end

    {
      options: options,
      date_variation: connection['dateVariation'],
      duration: connection['duration'],
      flights: flights,
    }
  end

  def get_bundle_overview(bundle)
    outbound_bundle = bundle[:outbound]
    cheapest_outbound_option = get_cheapest_option(outbound_bundle[:options])

    inbound_bundle = bundle[:inbound]
    inbound_overview = nil
    cheapest_inbound_price = 0

    time_format = '%H:%M'

    unless inbound_bundle.nil?
      cheapest_inbound_option = get_cheapest_option(inbound_bundle[:options])
      cheapest_inbound_price = cheapest_inbound_option[:price]

      inbound_overview = {
        departure_time: DateTime.parse(inbound_bundle[:flights].first[:departure_datetime]).strftime(time_format),
        arrival_time: DateTime.parse(inbound_bundle[:flights].last[:arrival_datetime]).strftime(time_format),
        date_variation: inbound_bundle[:date_variation],
        duration: inbound_bundle[:duration],
        price: cheapest_inbound_option[:price],
        class: cheapest_inbound_option[:class][:name],
        airports: get_airports(inbound_bundle[:flights]),
      }
    end

    {
      total_price: cheapest_outbound_option[:price] + cheapest_inbound_price,
      currency: @currency,
      outbound: {
        departure_time: DateTime.parse(outbound_bundle[:flights].first[:departure_datetime]).strftime(time_format),
        arrival_time: DateTime.parse(outbound_bundle[:flights].last[:arrival_datetime]).strftime(time_format),
        date_variation: outbound_bundle[:date_variation],
        duration: outbound_bundle[:duration],
        price: cheapest_outbound_option[:price],
        class: cheapest_outbound_option[:class][:name],
        airports: get_airports(outbound_bundle[:flights]),
      },
      inbound: inbound_overview
    }
  end

  def get_cheapest_option(options)
    options.min_by { |option| option[:price] }
  end

  def get_airports(flights)
    airports = []
    flights.each do |flight|
      airports << flight[:origin]
    end
    airports << flights.last[:destination]
  end

  def get_search_overview(bundles)
    get_cheapest_bundle(bundles)[:overview]
  end

  def get_cheapest_bundle(bundles)
    bundles.min_by { |bundle| bundle[:overview][:total_price] }
  end
end

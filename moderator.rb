class Moderator
  def filter(response_data, config_filters)
    unless is_filter(config_filters)
      return response_data
    end

    filter_data(response_data)
  end

  private

  def is_filter(config_filters)
    if config_filters.nil?
      return false
    end

    @filters = get_filters(config_filters)

    !(@filters[:price][:higher_than].nil? &&
      @filters[:price][:lower_than].nil? &&
      @filters[:duration][:higher_than].nil? &&
      @filters[:duration][:lower_than].nil? &&
      @filters[:stops][:higher_than].nil? &&
      @filters[:stops][:lower_than].nil?)
  end

  def get_filters(config_filters)
    {
      price: {
        higher_than: config_filters.dig('higher-than', 'price'),
        lower_than: config_filters.dig('lower-than', 'price'),
      },
      duration: {
        higher_than: config_filters.dig('higher-than', 'duration'),
        lower_than: config_filters.dig('lower-than', 'duration'),
      },
      stops: {
        higher_than: config_filters.dig('higher-than', 'stops'),
        lower_than: config_filters.dig('lower-than', 'stops'),
      }
    }
  end

  def filter_data(response_data)
    itineraries = response_data['itineraries']
    if itineraries.nil? || itineraries.empty?
      abort 'Unexpected JSON: No itineraries found'
    end

    filtered_itineraries = []
    itineraries.each do |itinerary|
      filtered_itinerary = filter_itinerary(itinerary)
      unless filtered_itinerary.nil?
        filtered_itineraries << filtered_itinerary
      end
    end
    response_data['itineraries'] = filtered_itineraries

    response_data
  end

  def filter_itinerary(itinerary)
    flightProducts = itinerary['flightProducts']
    if flightProducts.nil? || flightProducts.empty?
      abort 'Unexpected JSON: itineraries[i].flightProducts not found'
    end

    connections = itinerary['connections']
    if connections.nil? || connections.empty?
      abort 'Unexpected JSON: itineraries[i].connections not found'
    end

    outbound_connection = itinerary['connections'][0]
    inbound_connection = itinerary['connections'][1]
    unless is_connection_valid(outbound_connection) && is_connection_valid(inbound_connection)
      return nil
    end

    valid_products = flightProducts.reject { |flight_product| !is_product_valid(flight_product) }
    if valid_products.empty?
      return nil
    end
    itinerary['flightProducts'] = valid_products

    itinerary
  end

  # Only applies the filter if the connection is not nil
  def is_connection_valid(connection)
    if connection.nil?
      return true
    end

    if !@filters[:duration][:higher_than].nil? && (connection['duration'] > @filters[:duration][:higher_than])
      return false
    end
    if !@filters[:duration][:lower_than].nil? && (connection['duration'] < @filters[:duration][:lower_than])
      return false
    end

    stops = get_connection_stops(connection)
    if !@filters[:stops][:higher_than].nil? && (stops > @filters[:stops][:higher_than])
      return false
    end
    if !@filters[:stops][:lower_than].nil? && (stops < @filters[:stops][:lower_than])
      return false
    end

    true
  end

  def get_connection_stops(connection)
    segments = connection['segments']
    if segments.nil? || segments.empty?
      abort 'Unexpected JSON: itineraries[i].connections[j].segments not found'
    end

    return segments.length - 1
  end
  
  def is_product_valid(flight_product)
    if !@filters[:price][:higher_than].nil? && (flight_product['price']['totalPrice'] > @filters[:price][:higher_than])
      return false
    end
    if !@filters[:price][:lower_than].nil? && (flight_product['price']['totalPrice'] < @filters[:price][:lower_than])
      return false
    end

    true
  end
end

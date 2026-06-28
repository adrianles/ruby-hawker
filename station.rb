class Station
  CITY_CODES = {
    'BUE' => 'Buenos Aires',
    'CHI' => 'Chicago',
    'LON' => 'London',
    'MIL' => 'Milan',
    'MOW' => 'Moscow',
    'NYC' => 'New York',
    'OSA' => 'Osaka',
    'PAR' => 'Paris',
    'RIO' => 'Rio de Janeiro',
    'ROM' => 'Rome',
    'SAO' => 'Sao Paulo',
    'SEL' => 'Seoul',
    'TYO' => 'Tokyo',
    'WAS' => 'Washington',
    'YMQ' => 'Montreal',
    'YTO' => 'Toronto',
  }.freeze

  def self.from_config(value)
    {
      ConfigDefinition::SEARCH_STATION_CODE => value,
      ConfigDefinition::SEARCH_STATION_TYPE => CITY_CODES.key?(value) ? 'CITY' : 'AIRPORT',
    }
  end
end

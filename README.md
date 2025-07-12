## About

The Hawker app will fetch flight information from https://developer.airfranceklm.com APIs.
It is intended to be used to search for a specific flight in different dates and compare prices.

You will be able to set up some parameters in terms of flight origin and destination and in terms of dates.
Then Hawker will fetch the information and format it in JSON.

You only need to obtain an API key from their website by creating a free account.
The free account is rate limited to 1 request per second and 100 requests per day.

## Usage

Copy the `search_config.json.template` file and name it `search_config.json`.

Add your personal API key and the desired search settings to the `search_config.json` file.

You can then use the `capture` function to find the information for specific dates.
Capture will search for:
- outbound flights in the specified outbound date (only one day)
- and (if `return = true`) inbound flights in the specified inbound date (only one day)
```bash
# Example:
ruby hunt_command.rb capture
```

You can also use the `hunt` function to find the all the information between specifified dates.
Hunt will search for:
- outbound flights in the specified range of dates, from outbound date to inbound date (multiple days)
- inbound flights in the specified range of dates, from outbound date to inbound date (multiple days)
This way you can compare the prices for all days for both outbound and inbound flights.
```bash
# Example:
ruby hunt_command.rb hunt
```

The formatted response will be written to `data/output/{current_timestamp}.json`.
You can also find the full raw output of the search request in `data/response/{current_timestamp}.json`.
For the `hunt` command, a csv file will be created with the dates and the minimun price for each day at `data/output/{current_timestamp}.csv`.

TODO tasks:
- improve number of request done in hunt by searching 1-1, 2-2, 3-3 instead of 1-3, 2-3, 3-3, 1-1, 1-2, 1-3 (double check if prices are the same first)
- meta info on how many calls in a day (one day UTC)
- write in per day folder

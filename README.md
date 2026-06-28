## About

The Hawker app will fetch flight information from https://developer.airfranceklm.com APIs.
It is intended to be used to search for a specific flight in different dates and compare prices.

You will be able to set up some parameters in terms of flight origin and destination and in terms of dates.
Then Hawker will fetch the information and format it in JSON.

You only need to obtain an API key from their website by creating a free account.
The free account is rate limited to 1 request per second and 100 requests per day.
- The app will atomatically count and stop doing requests once the limit is reached. You can look at the count in the `request_count.json` file.
- You can configure more than one API keys. The app will use all of them. This can help you increase the requests per second and the daily limit.

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

You can also use the `hunt` function to search the configured route across a range of dates.
Hunt will search for:
- flights from `from` to `to` in the specified range of dates, from outbound date to inbound date (multiple days)
- if `return = false`, one-way prices
- if `return = true`, return-trip prices using a calculated return date 7 days after each searched date

To search the opposite direction, swap `from` and `to` in `search_config.json` and run `hunt` again.
```bash
# Example:
ruby hunt_command.rb hunt
```

The formatted response will be written to `data/output/{current_timestamp}-{search_suffix}.json`.
You can also find the full raw output of the search request in `data/response/{current_timestamp}-{search_suffix}.json`.
For example, `hunt` writes files like `data/output/{current_timestamp}-hunt-{date}.json`.
For the `hunt` command, a csv file will be created with the dates and the minimum price for each day at `data/output/{current_timestamp}-summary.csv`.

TODO tasks:
- write in per day folder

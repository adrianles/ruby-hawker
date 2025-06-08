## About

The Hawker app will fetch flight information from https://developer.airfranceklm.com APIs.
It is intended to be used to search for a specific flight in different dates and compare prices.

You will be able to set up some parameters in terms of flight origin and destination and in terms of dates.
Then Hawker will fetch the information and format it in JSON.

You only need to obtain an API key from their website by creating a free account.

## Usage

Copy the `search_config.json.template` file and name it `search_config.json`.

Add your personal API key and the desired search settings to the `search_config.json` file.

And then run your search like this:

```bash
# Example:
ruby hunt_command.rb hunt
```

The formatted response will be written to `data/output/{timestamp}.json`.
You can also find the full raw output of the search request in `data/response/{timestamp}.json`.

# AI Context: Hawker

Hawker is a small Ruby CLI app for searching Air France/KLM flight offers across dates, filtering results, and writing formatted JSON/CSV outputs.

## Purpose

The app searches for flights across a range of dates to help find the best options, usually the cheapest flights. Before it can run, it requires a specific local configuration in `search_config.json`.

`hunt` searches one configured travel direction at a time: `from -> to`. To search the opposite direction, swap `from` and `to` in `search_config.json` and run `hunt` again.

## Runtime

- Language: Ruby
- CLI framework: `thor`
- HTTP client: `httparty`
- Entry point: `hunt_command.rb`
- Install dependencies with `bundle install`
- Main commands:
  - `ruby hunt_command.rb hunt`
  - `ruby hunt_command.rb capture`

## Main Flow

`HuntCommand` in `hunt_command.rb` is the orchestrator.

1. Loads the required local `search_config.json`.
2. Reads API keys and search settings.
3. Uses `Licenser` to choose an API key and enforce rate/daily limits.
4. Uses `Applicant` to call the Air France/KLM available-offers API.
5. Uses `Moderator` to filter raw itineraries.
6. Uses `Smith` to format filtered API data.
7. Writes raw responses to `data/response/*-{search_suffix}.json`.
8. Writes formatted outputs to `data/output/*-{search_suffix}.json`.
9. For `hunt`, writes min-price CSV to `data/output/*-summary.csv`.

## Important Files

- `hunt_command.rb`: Thor CLI commands and orchestration.
- `applicant.rb`: Builds and sends the AF/KLM API request.
- `moderator.rb`: Applies exclude filters for price, duration, and stops.
- `smith.rb`: Converts raw API itinerary data into the app's output shape.
- `licenser.rb`: Tracks request counts per API key and calculates wait times.
- `config_definition.rb`: String constants for config keys.
- `search_config.json.template`: Example search config, but currently not valid JSON because it contains comments and unquoted object keys.
- `README.md`: User-facing project description and usage notes.

## Config And Local State

Ignored local files:

- `search_config.json`: Real user config with API keys.
- `request_count.json`: Per-key, per-day request counts.
- `data/*`: Generated API responses and outputs.

Expected `search_config.json` structure:

- Top level:
  - `api-keys`: array of API key strings.
  - `search`: search settings.
- Search settings:
  - `from`: object with `code` and `type`.
  - `to`: object with `code` and `type`.
  - `return`: boolean; for `hunt`, `false` means one-way pricing and `true` means return-trip pricing with a calculated reverse leg.
  - `outboundDate`: `YYYY-MM-DD` or `null`; for `hunt`, this is the start of the searched date range.
  - `inboundDate`: `YYYY-MM-DD` or `null`; for `hunt`, this is the end of the searched date range.
  - `exclude`: optional filters.

## Known Gotchas

- `search_config.json.template` is not parseable JSON as written.
- Several methods use `abort`, so malformed API responses or missing files terminate the process.
- Output directories `data/response` and `data/output` must exist before writes.
- There are no automated tests in the repo at the moment.

## Domain Notes

The AF/KLM API endpoint used is:

`https://api.airfranceklm.com/opendata/offers/v2/available-offers`

`Applicant` sends:

- `commercialCabins: ["ALL"]`
- `bookingFlow: "LEISURE"`
- one adult passenger
- one requested connection for one-way searches
- two requested connections for return searches
- currency currently hardcoded to `EUR` by `HuntCommand`

For `hunt`, `return: true` still searches only the configured direction, but sends a return-style API request so the price reflects return-trip pricing. The reverse leg is calculated as `searched_date + HUNT_PAIRING_GAP_DAYS`, currently 7 days, and is not the result being optimized. For `return: false`, `hunt` sends a true one-way request.

Current output suffixes:

- `hunt`: `hunt-YYYY-MM-DD`
- `capture`: `capture-YYYY-MM-DD` or `capture-YYYY-MM-DD-YYYY-MM-DD`
- `hunt` CSV: `summary`

## Development Style

The repo is simple, script-like Ruby. Prefer small, direct changes over new abstractions. Keep behavior centered around `HuntCommand` unless a helper already owns the concern.


## Usage

Copy the `search_config.json.template` file and name it `search_config.json`.

Add your settings to the `search_config.json` file.
And then run your search like this:

```bash
# Example:
ruby hunt_command.rb hunt
```

The formatted response will be written to `data/output/{timestamp}.json`.
You can also find the full output of the search request in `data/response/{timestamp}.json`.

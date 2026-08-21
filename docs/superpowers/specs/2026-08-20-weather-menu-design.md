# Weather Menu Design

## Goal

The weather plugin will show current conditions and forecasts in its status-item menu. The status item will remain compact.

## Data

The plugin will request the existing wttr.in provider with `format=j1`. One response contains current conditions, hourly forecasts, and daily forecasts.

The plugin will obey the measurement setting from `macotron.system.locale()`. It will use Fahrenheit and miles for US units. It will use Celsius and kilometers for metric units.

## Status Item

The status item will show an SF Symbol and the current temperature. The symbol will represent the current weather condition.

If a request fails before any successful response, the status item will show an error state. After a successful response, a later error will retain the last weather data.

## Menu

The menu will contain these sections:

1. The resolved location and current weather description.
2. The feels-like temperature, humidity, wind, UV index, and visibility.
3. A `Next 12 Hours` submenu with four forecasts at three-hour intervals.
4. Three daily forecasts with a condition symbol and minimum and maximum temperatures.
5. A `Refresh` action.

The plugin will map provider weather codes to a small set of SF Symbols. It will use native menu separators between sections.

## Error Handling

Invalid or incomplete provider data will produce a controlled error. The menu will show the last update error without removing cached weather data.

## Tests and Verification

Tests will cover JSON parsing, unit selection, weather symbols, and hourly forecast selection. `make build` and the full test suite must complete without errors.

The final step will copy the updated plugin to `tmp/macotron/plugins/weather.js`. A file comparison will make sure that both copies are identical.

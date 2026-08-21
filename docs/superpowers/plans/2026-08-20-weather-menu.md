# Weather Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add current details, a 12-hour forecast, and a three-day forecast to the weather menu.

**Architecture:** The weather plugin will request the wttr.in `j1` response and convert it to native menu rows. Small pure functions will select units, map weather codes to SF Symbols, and select forecast periods. An end-to-end QuickJS test will operate the plugin with a fixed provider response.

**Tech Stack:** JavaScript in QuickJS, Swift Testing, Macotron menu-bar APIs, wttr.in JSON

## Global Constraints

- Use only APIs that work on a stock Mac with Macotron installed.
- Do not add dependencies.
- Keep all production logic in `Examples/plugins/weather.js`.
- Retain the last successful response after a later request error.
- Run `make` before completion.
- Copy the final plugin to `tmp/macotron/plugins/weather.js`.
- Do not create a git commit unless the user asks for one.

---

### Task 1: Weather menu behavior test

**Files:**
- Create: `Tests/MacotronTests/WeatherTests.swift`
- Read: `Examples/plugins/weather.js`

**Interfaces:**
- Consumes: the top-level plugin script and a stub `macotron` object.
- Produces: coverage for JSON parsing, US and metric units, symbols, hourly selection, daily rows, and refresh errors.

- [ ] **Step 1: Add a fixed wttr.in response**

Add a compact response with current conditions, one resolved location, three daily forecasts, and hourly entries across two days.

- [ ] **Step 2: Add a QuickJS harness**

Read the plugin file from the repository. Define a `macotron` stub that captures the request URL and status configuration. Return the fixed response from `macotron.http.get`.

- [ ] **Step 3: Add failing assertions**

Assert these values:

```swift
#expect(value("capturedURL.includes('format=j1')") == "true")
#expect(value("statusConfig.sfSymbol") == "cloud.sun.fill")
#expect(value("statusConfig.menu.find(x => x.title === 'Next 12 Hours').menu.length") == "4")
#expect(value("statusConfig.menu.filter(x => /°–.*°/.test(x.title)).length") == "3")
```

Run:

```bash
swift test --build-path /tmp/macotron-build --filter WeatherTests
```

Expected: FAIL because the current plugin requests formatted text and only adds a Refresh row.

- [ ] **Step 4: Add unit and error assertions**

Load the script once with metric units and once with US units. Assert Celsius/kilometer output for metric and Fahrenheit/mile output for US.

After a successful request, reject the next request and invoke `refreshWeather()`. Assert that the previous temperature remains and the menu gains an error row.

---

### Task 2: JSON weather menu

**Files:**
- Modify: `Examples/plugins/weather.js`
- Test: `Tests/MacotronTests/WeatherTests.swift`

**Interfaces:**
- Produces: `weatherSymbol(code)`, `forecastHours(weather, observation)`, `weatherMenu(data, units, error)`, and `refreshWeather()`.

- [ ] **Step 1: Request one JSON response**

Use this URL shape:

```js
const url = `https://wttr.in/${path}?format=j1`;
```

Parse `res.body` and reject responses without `current_condition[0]` or `weather`.

- [ ] **Step 2: Map provider conditions to SF Symbols**

Map clear, partly cloudy, cloudy, fog, rain, thunder, snow, and sleet code groups. Return `cloud.fill` for an unknown code.

- [ ] **Step 3: Format current conditions**

Select temperature, feels-like, wind speed, and visibility fields from the locale measurement setting. Show the resolved location, condition, humidity, wind, UV index, and visibility.

- [ ] **Step 4: Select the next 12 hours**

Flatten the provider hourly entries across forecast days. Use the observation date and time as the selection point. Return the next four three-hour entries.

- [ ] **Step 5: Format forecast sections**

Add a `Next 12 Hours` submenu with four entries. Add three daily rows with day labels, condition symbols, and minimum and maximum temperatures.

- [ ] **Step 6: Retain successful data on errors**

Store the last valid response. If a later request fails, render the stored response and add an error row. If no response exists, show a red error status with Refresh.

- [ ] **Step 7: Run the focused test**

Run:

```bash
swift test --build-path /tmp/macotron-build --filter WeatherTests
```

Expected: PASS.

---

### Task 3: Full verification and plugin sync

**Files:**
- Copy: `Examples/plugins/weather.js`
- Write: `tmp/macotron/plugins/weather.js`

**Interfaces:**
- Consumes: the completed plugin and test.
- Produces: a buildable repository and an identical workdir plugin.

- [ ] **Step 1: Run the complete build and tests**

Run:

```bash
make build
swift test --build-path /tmp/macotron-build
```

Expected: the Swift build and test suite complete without errors.

- [ ] **Step 2: Check the plugin with the host**

Run:

```bash
make check ARGS='Examples/plugins/weather.js'
```

Expected: the plugin passes the host check.

- [ ] **Step 3: Copy the plugin**

Run:

```bash
cp Examples/plugins/weather.js tmp/macotron/plugins/weather.js
```

- [ ] **Step 4: Compare both files**

Run:

```bash
cmp Examples/plugins/weather.js tmp/macotron/plugins/weather.js
```

Expected: exit status 0 with no output.

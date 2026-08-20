import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("WeatherDemoTests")
struct WeatherDemoTests {
    private static let fixture = #"""
    {
      "current_condition": [{
        "temp_C": "18", "temp_F": "64",
        "FeelsLikeC": "17", "FeelsLikeF": "63",
        "humidity": "61", "windspeedKmph": "18", "windspeedMiles": "11",
        "uvIndex": 4, "visibility": "12", "visibilityMiles": "7",
        "weatherCode": "116", "weatherDesc": [{"value": "Partly cloudy"}],
        "observation_time": "03:30 AM",
        "localObsDateTime": "2026-08-20 08:30 PM"
      }],
      "nearest_area": [{
        "areaName": [{"value": "Seattle"}],
        "region": [{"value": "Washington"}],
        "country": [{"value": "United States"}]
      }],
      "weather": [
        {
          "date": "2026-08-20", "mintempC": "13", "maxtempC": "21",
          "mintempF": "55", "maxtempF": "70",
          "hourly": [
            {"time": "1200", "tempC": "20", "tempF": "68", "weatherCode": "389", "weatherDesc": [{"value": "Thunder"}]},
            {"time": "1800", "tempC": "19", "tempF": "66", "weatherCode": "113", "weatherDesc": [{"value": "Clear"}]},
            {"time": "2100", "tempC": "16", "tempF": "61", "weatherCode": "116", "weatherDesc": [{"value": "Partly cloudy"}]}
          ]
        },
        {
          "date": "2026-08-21", "mintempC": "12", "maxtempC": "20",
          "mintempF": "54", "maxtempF": "68",
          "hourly": [
            {"time": "0", "tempC": "15", "tempF": "59", "weatherCode": "119", "weatherDesc": [{"value": "Cloudy"}]},
            {"time": "300", "tempC": "14", "tempF": "57", "weatherCode": "143", "weatherDesc": [{"value": "Fog"}]},
            {"time": "600", "tempC": "13", "tempF": "55", "weatherCode": "296", "weatherDesc": [{"value": "Rain"}]},
            {"time": "1200", "tempC": "17", "tempF": "63", "weatherCode": "338", "weatherDesc": [{"value": "Snow"}]}
          ]
        },
        {
          "date": "2026-08-22", "mintempC": "11", "maxtempC": "19",
          "mintempF": "52", "maxtempF": "66",
          "hourly": [
            {"time": "1200", "tempC": "16", "tempF": "61", "weatherCode": "350", "weatherDesc": [{"value": "Sleet"}]}
          ]
        }
      ]
    }
    """#

    @MainActor
    private final class Harness {
        let engine = Engine()

        init(measurement: String, localObservation: Bool = true) throws {
            let repository = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let demoURL = repository.appending(path: "Examples/plugins/demo-weather.js")
            let demo = try String(contentsOf: demoURL, encoding: .utf8)
            let source = """
                var capturedURLs = [];
                var statusConfig = null;
                var rejectNextRequest = false;
                var responseData = \(WeatherDemoTests.fixture);
                if (!\(localObservation)) delete responseData.current_condition[0].localObsDateTime;
                var responseBody = JSON.stringify(responseData);
                var fallbackTime = "20:30:00-0700";
                var commandHandler = null;
                var toasts = [];
                var macotron = {
                    plugin: () => ({ location: "Seattle", refreshMs: 600000 }),
                    http: {
                        get: (url) => {
                            capturedURLs.push(url);
                            if (rejectNextRequest) {
                                rejectNextRequest = false;
                                return Promise.reject(new Error("offline"));
                            }
                            if (url.includes("format=%T")) {
                                return Promise.resolve({ status: 200, body: fallbackTime });
                            }
                            return Promise.resolve({
                                status: 200,
                                body: responseBody
                            });
                        }
                    },
                    menubar: { status: (_, config) => { statusConfig = config; } },
                    system: { locale: () => ({ measurement: "\(measurement)" }) },
                    every: () => {},
                    notify: { toast: (...args) => { toasts.push(args); } },
                    command: (title, detail, handler) => { commandHandler = handler; },
                    log: () => {}
                };
                \(demo)
                """
            let (_, error) = engine.evaluate(source, filename: demoURL.path)
            if let error {
                throw HarnessError.evaluation(error)
            }
        }

        func value(_ expression: String) -> String? {
            let (result, _) = engine.evaluate(expression)
            return result
        }
    }

    private enum HarnessError: Error {
        case evaluation(String)
    }

    @Test("renders JSON forecasts with metric units")
    func metricForecast() throws {
        let harness = try Harness(measurement: "metric")

        func value(_ expression: String) -> String? {
            harness.value(expression)
        }

        #expect(value("capturedURLs.length") == "1")
        #expect(value("capturedURLs[0].includes('format=j1')") == "true")
        #expect(value("statusConfig.sfSymbol") == "cloud.sun.fill")
        #expect(value("statusConfig.menu.find(x => x.title === 'Next 12 Hours').menu.length") == "4")
        #expect(value("""
            JSON.stringify(
                statusConfig.menu
                    .find(x => x.title === 'Next 12 Hours')
                    .menu
                    .map(x => [
                        x.title.match(/(?:9 PM|12 AM|3 AM|6 AM)/)[0],
                        x.title.match(/\\d+°/)[0]
                    ])
            )
            """) == #"[["9 PM","16°"],["12 AM","15°"],["3 AM","14°"],["6 AM","13°"]]"#)
        #expect(value("statusConfig.menu.filter(x => /°–.*°/.test(x.title)).length") == "3")
        #expect(value("""
            JSON.stringify(
                statusConfig.menu
                    .filter(x => /°–.*°/.test(x.title))
                    .map(x => [x.title.match(/(?:Thunder|Snow|Sleet)/)[0], x.icon])
            )
            """) == #"[["Thunder","cloud.bolt.rain.fill"],["Snow","cloud.snow.fill"],["Sleet","cloud.sleet.fill"]]"#)
        #expect(value("statusConfig.title.includes('18°')") == "true")
        #expect(value("statusConfig.menu.some(x => /12 km/.test(x.title))") == "true")
    }

    @Test("renders US temperatures and distances")
    func usUnits() throws {
        let harness = try Harness(measurement: "us")

        #expect(harness.value("statusConfig.title.includes('64°')") == "true")
        #expect(harness.value("statusConfig.menu.some(x => /Feels like 63°/.test(x.title))") == "true")
        #expect(harness.value("statusConfig.menu.some(x => /Wind 11 mph/.test(x.title))") == "true")
        #expect(harness.value("statusConfig.menu.some(x => /7 miles/.test(x.title))") == "true")
        #expect(harness.value("""
            JSON.stringify(
                statusConfig.menu
                    .find(x => x.title === 'Next 12 Hours')
                    .menu
                    .map(x => x.title.match(/\\d+°/)[0])
            )
            """) == #"["61°","59°","57°","55°"]"#)
        #expect(harness.value("""
            JSON.stringify(
                statusConfig.menu
                    .filter(x => /°–.*°/.test(x.title))
                    .map(x => x.title.match(/\\d+°–\\d+°/)[0])
            )
            """) == #"["55°–70°","54°–68°","52°–66°"]"#)
    }

    @Test("maps every weather condition group")
    func weatherSymbols() throws {
        let harness = try Harness(measurement: "metric")

        #expect(harness.value("""
            JSON.stringify(
                [113, 116, 119, 143, 296, 389, 338, 350, 999]
                    .map(weatherSymbol)
            )
            """) == #"["sun.max.fill","cloud.sun.fill","cloud.fill","cloud.fog.fill","cloud.rain.fill","cloud.bolt.rain.fill","cloud.snow.fill","cloud.sleet.fill","cloud.fill"]"#)
    }

    @Test("retains weather after a refresh error")
    func refreshError() throws {
        let harness = try Harness(measurement: "metric")
        let previousTitle = harness.value("statusConfig.title")
        let previousMenu = harness.value("""
            JSON.stringify(
                statusConfig.menu,
                (_, value) => typeof value === 'function' ? undefined : value
            )
            """)

        #expect(harness.value("rejectNextRequest = true; refreshWeather(); 'requested'") == "requested")
        #expect(harness.value("statusConfig.title") == previousTitle)
        #expect(harness.value("""
            JSON.stringify(
                statusConfig.menu.filter(x => !/error|failed/i.test(x.title)),
                (_, value) => typeof value === 'function' ? undefined : value
            )
            """) == previousMenu)
        #expect(harness.value("statusConfig.menu.filter(x => /error|failed/i.test(x.title)).length") == "1")
    }

    @Test("uses provider local-time fallback when local observation is absent")
    func localTimeFallback() throws {
        let harness = try Harness(measurement: "metric", localObservation: false)
        let expected = #"[["9 PM","16°"],["12 AM","15°"],["3 AM","14°"],["6 AM","13°"]]"#

        #expect(harness.value("capturedURLs.length") == "2")
        #expect(harness.value("capturedURLs[0].includes('format=j1')") == "true")
        #expect(harness.value("capturedURLs[1].includes('format=%T')") == "true")
        #expect(harness.value("lastObservation") == "20:30:00-0700")
        #expect(harness.value("observationKey(responseData.weather, '20:30:00-0760') === null") == "true")
        #expect(harness.value("""
            JSON.stringify(
                statusConfig.menu
                    .find(x => x.title === 'Next 12 Hours')
                    .menu
                    .map(x => [
                        x.title.match(/(?:9 PM|12 AM|3 AM|6 AM)/)[0],
                        x.title.match(/\\d+°/)[0]
                    ])
            )
            """) == expected)

        let previousMenu = harness.value("""
            JSON.stringify(
                statusConfig.menu,
                (_, value) => typeof value === 'function' ? undefined : value
            )
            """)
        #expect(harness.value("rejectNextRequest = true; refreshWeather(); 'requested'") == "requested")
        #expect(harness.value("""
            JSON.stringify(
                statusConfig.menu.filter(x => !/error|failed/i.test(x.title)),
                (_, value) => typeof value === 'function' ? undefined : value
            )
            """) == previousMenu)
    }

    @Test("rejects incomplete responses without replacing cached weather")
    func incompleteResponse() throws {
        let harness = try Harness(measurement: "metric")
        let previousTitle = harness.value("statusConfig.title")

        #expect(harness.value("responseBody = '{\"current_condition\":[{}],\"weather\":[]}'; refreshWeather(); 'requested'") == "requested")
        #expect(harness.value("statusConfig.title") == previousTitle)
        #expect(harness.value("lastWeather.weather.length") == "3")
        #expect(harness.value("statusConfig.menu.filter(x => /error|failed/i.test(x.title)).length") == "1")

        #expect(harness.value("lastWeather = null; refreshWeather(); 'requested'") == "requested")
        #expect(harness.value("lastWeather === null") == "true")
        #expect(harness.value("statusConfig.color") == "red")
    }

    @Test("rejects skipped or irregular forecast periods")
    func irregularForecastPeriods() throws {
        let skipped = try Harness(measurement: "metric")
        let skippedMenu = skipped.value("""
            JSON.stringify(
                statusConfig.menu,
                (_, value) => typeof value === 'function' ? undefined : value
            )
            """)
        #expect(skipped.value("""
            responseData.weather[1].hourly.splice(1, 1);
            responseBody = JSON.stringify(responseData);
            refreshWeather();
            'requested'
            """) == "requested")
        #expect(skipped.value("""
            JSON.stringify(
                statusConfig.menu.filter(x => !/error|failed/i.test(x.title)),
                (_, value) => typeof value === 'function' ? undefined : value
            )
            """) == skippedMenu)
        #expect(skipped.value("statusConfig.menu.filter(x => /error|failed/i.test(x.title)).length") == "1")

        let irregular = try Harness(measurement: "metric")
        let irregularMenu = irregular.value("""
            JSON.stringify(
                statusConfig.menu,
                (_, value) => typeof value === 'function' ? undefined : value
            )
            """)
        #expect(irregular.value("""
            responseData.weather[1].hourly[1].time = '400';
            responseBody = JSON.stringify(responseData);
            refreshWeather();
            'requested'
            """) == "requested")
        #expect(irregular.value("""
            JSON.stringify(
                statusConfig.menu.filter(x => !/error|failed/i.test(x.title)),
                (_, value) => typeof value === 'function' ? undefined : value
            )
            """) == irregularMenu)
        #expect(irregular.value("statusConfig.menu.filter(x => /error|failed/i.test(x.title)).length") == "1")
    }

    @Test("rejects malformed numeric date and time values")
    func malformedProviderValues() throws {
        let harness = try Harness(measurement: "metric")
        let previousMenu = harness.value("""
            JSON.stringify(
                statusConfig.menu,
                (_, value) => typeof value === 'function' ? undefined : value
            )
            """)

        for mutation in [
            "responseData.current_condition[0].temp_C = ''",
            "responseData.current_condition[0].temp_C = 'abc'",
            "responseData.current_condition[0].temp_C = '18'; responseData.weather[0].date = '2026-02-30'",
            "responseData.weather[0].date = '2026-08-20'; responseData.weather[1].hourly[1].time = '2460'",
        ] {
            #expect(harness.value("\(mutation); responseBody = JSON.stringify(responseData); refreshWeather(); 'requested'") == "requested")
            #expect(harness.value("""
                JSON.stringify(
                    statusConfig.menu.filter(x => !/error|failed/i.test(x.title)),
                    (_, value) => typeof value === 'function' ? undefined : value
                )
                """) == previousMenu)
            #expect(harness.value("statusConfig.menu.filter(x => /error|failed/i.test(x.title)).length") == "1")
        }
    }

    @Test("rejects malformed local time without replacing cached weather")
    func malformedLocalTime() throws {
        let harness = try Harness(measurement: "metric")
        let previousMenu = harness.value("""
            JSON.stringify(
                statusConfig.menu,
                (_, value) => typeof value === 'function' ? undefined : value
            )
            """)

        #expect(harness.value("""
            responseData.current_condition[0].localObsDateTime = 'not-a-time';
            responseBody = JSON.stringify(responseData);
            refreshWeather();
            'requested'
            """) == "requested")
        #expect(harness.value("capturedURLs.filter(x => x.includes('format=%T')).length") == "0")
        #expect(harness.value("lastObservation") == "2026-08-20 08:30 PM")
        #expect(harness.value("""
            JSON.stringify(
                statusConfig.menu.filter(x => !/error|failed/i.test(x.title)),
                (_, value) => typeof value === 'function' ? undefined : value
            )
            """) == previousMenu)
        #expect(harness.value("statusConfig.menu.filter(x => /error|failed/i.test(x.title)).length") == "1")
    }

    @Test("reports refresh result and failure toast")
    func refreshResult() throws {
        let harness = try Harness(measurement: "metric")

        #expect(harness.value("var refreshResult; rejectNextRequest = true; refreshWeather().then(x => { refreshResult = x; }); 'requested'") == "requested")
        #expect(harness.value("refreshResult") == "false")

        #expect(harness.value("rejectNextRequest = true; commandHandler(); 'requested'") == "requested")
        #expect(harness.value("toasts[toasts.length - 1][1]") == "Update failed")
        #expect(harness.value("toasts[toasts.length - 1][2].color") == "error")
    }
}

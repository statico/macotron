import Testing
@testable import MacotronEngine

@MainActor
@Suite("Command arguments")
struct CommandArgumentTests {
    @Test("eval without a plugin file keys the registry by name")
    func evalUsesNameAsId() {
        let engine = Engine()
        engine.evaluate("""
            $$__registerCommand("greet", "Says hello", function() {}, {});
        """)
        #expect(engine.commandRegistry["greet"] != nil)
        #expect(engine.commandRegistry["greet"]?.id == "greet")
        #expect(engine.commandRegistry["greet"]?.name == "greet")
        #expect(engine.commandRegistry["greet"]?.pluginFile == "")
        #expect(engine.commandRegistry["greet"]?.arguments.isEmpty == true)
    }

    @Test("plugin file prefixes the default id")
    func pluginFilePrefixesId() {
        let engine = Engine()
        engine.currentEvaluatingFile = "lorem.js"
        engine.evaluate("""
            $$__registerCommand("Generate Lorem Ipsum", "text", function() {}, {});
        """)
        #expect(engine.commandRegistry["lorem.js/Generate Lorem Ipsum"] != nil)
        #expect(engine.commandRegistry["Generate Lorem Ipsum"] == nil)
    }

    @Test("opts.id overrides the default id")
    func explicitIdWins() {
        let engine = Engine()
        engine.currentEvaluatingFile = "lorem.js"
        engine.evaluate("""
            $$__registerCommand("Generate Lorem Ipsum", "text", function() {}, { id: "lorem-ipsum" });
        """)
        #expect(engine.commandRegistry["lorem-ipsum"] != nil)
        #expect(engine.commandRegistry["lorem-ipsum"]?.name == "Generate Lorem Ipsum")
    }

    @Test("parses text, number, and dropdown arguments")
    func parsesArgumentSpecs() {
        let engine = Engine()
        engine.evaluate("""
            $$__registerCommand("Lorem", "text", function() {}, {
              arguments: [
                { name: "count", type: "number", placeholder: "Count", default: 3 },
                { name: "unit", type: "dropdown", placeholder: "Unit", default: "words",
                  choices: [
                    { title: "Words", value: "words" },
                    { label: "Paragraphs", value: "paragraphs" }
                  ]
                }
              ]
            });
        """)
        let args = engine.commandRegistry["Lorem"]?.arguments ?? []
        #expect(args.count == 2)
        #expect(args[0].name == "count")
        #expect(args[0].type == "number")
        #expect(args[0].placeholder == "Count")
        #expect(args[0].required == false)
        if case .number(let n) = args[0].defaultValue { #expect(n == 3) } else { Issue.record("count default") }
        #expect(args[1].choices.map(\.value) == ["words", "paragraphs"])
        #expect(args[1].choices.map(\.title) == ["Words", "Paragraphs"])
    }

    @Test("skips arguments with no name and dropdowns with no choices")
    func skipsInvalidArguments() {
        let list = CommandArgumentSpec.parseList([
            ["type": "text"],
            ["name": "ok", "type": "text"],
            ["name": "empty-dd", "type": "dropdown"],
        ])
        #expect(list.map(\.name) == ["ok"])
    }

    @Test("resolver fills defaults and coerces numbers")
    func resolverUsesDefaults() {
        let specs = [
            CommandArgumentSpec(name: "count", type: "number", placeholder: "Count", defaultValue: .number(3)),
            CommandArgumentSpec(
                name: "unit", type: "dropdown", placeholder: "Unit",
                defaultValue: .string("words"),
                choices: [CommandArgumentChoice(title: "Words", value: "words")]
            ),
        ]
        let result = CommandArgumentResolver.resolve(specs: specs, raw: [:])
        guard case .success(let values) = result else {
            Issue.record("expected success")
            return
        }
        #expect(values["count"] as? Int == 3)
        #expect(values["unit"] as? String == "words")
    }

    @Test("resolver rejects missing required args")
    func resolverRejectsMissingRequired() {
        let specs = [
            CommandArgumentSpec(name: "q", type: "text", placeholder: "Query", required: true),
        ]
        let result = CommandArgumentResolver.resolve(specs: specs, raw: [:])
        guard case .failure(.missingRequired("q")) = result else {
            Issue.record("expected missingRequired")
            return
        }
    }

    @Test("invokeCommand passes an args object to JS")
    func invokePassesArgs() {
        let engine = Engine()
        engine.evaluate("""
            var seen = null;
            $$__registerCommand("echo", "echo", function(args) { seen = args; }, {});
        """)
        #expect(engine.invokeCommand("echo", args: ["count": 3, "unit": "words"]))
        let unit = engine.evaluate("seen.unit").0
        let count = engine.evaluate("String(seen.count)").0
        #expect(unit == "words")
        #expect(count == "3")
    }
}

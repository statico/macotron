// NLClassifierTests.swift — Tests for launcher input classification
import Testing
@testable import MacotronEngine

@MainActor
@Suite("NLClassifier Tests")
struct NLClassifierTests {

    // MARK: - Command Classification

    @Test("Exact command match returns .command")
    func testExactCommandMatch() {
        let classifier = NLClassifier()
        classifier.setKnownCommands(["reload", "quit", "help"])
        #expect(classifier.classify("reload") == .command)
    }

    @Test("Exact command match is case insensitive")
    func testCommandCaseInsensitive() {
        let classifier = NLClassifier()
        classifier.setKnownCommands(["reload"])
        #expect(classifier.classify("Reload") == .command)
        #expect(classifier.classify("RELOAD") == .command)
    }

    @Test("Command match with leading/trailing whitespace")
    func testCommandWithWhitespace() {
        let classifier = NLClassifier()
        classifier.setKnownCommands(["reload"])
        #expect(classifier.classify("  reload  ") == .command)
    }

    @Test("Unknown single word is not classified as command")
    func testUnknownWordNotCommand() {
        let classifier = NLClassifier()
        classifier.setKnownCommands(["reload"])
        #expect(classifier.classify("foobar") != .command)
    }

    // MARK: - Natural Language (chat prefix ">")

    @Test("Chat prefix '>' returns .naturalLang")
    func testChatPrefix() {
        let classifier = NLClassifier()
        #expect(classifier.classify(">hello") == .naturalLang)
    }

    @Test("Chat prefix '>' with space returns .naturalLang")
    func testChatPrefixWithSpace() {
        let classifier = NLClassifier()
        #expect(classifier.classify("> tell me about windows") == .naturalLang)
    }

    @Test("Chat prefix '>' alone returns .naturalLang")
    func testChatPrefixAlone() {
        let classifier = NLClassifier()
        #expect(classifier.classify(">") == .naturalLang)
    }

    // MARK: - Natural Language (question format)

    @Test("Question starting with 'what' returns .naturalLang")
    func testQuestionWhat() {
        let classifier = NLClassifier()
        #expect(classifier.classify("what windows are open") == .naturalLang)
    }

    @Test("Question starting with 'how' returns .naturalLang")
    func testQuestionHow() {
        let classifier = NLClassifier()
        #expect(classifier.classify("how do I tile windows") == .naturalLang)
    }

    @Test("Question starting with 'why' returns .naturalLang")
    func testQuestionWhy() {
        let classifier = NLClassifier()
        #expect(classifier.classify("why is the CPU hot") == .naturalLang)
    }

    @Test("Question starting with 'can you' returns .naturalLang")
    func testQuestionCanYou() {
        let classifier = NLClassifier()
        #expect(classifier.classify("can you move the window") == .naturalLang)
    }

    @Test("Sentence starting with 'please' returns .naturalLang")
    func testPlease() {
        let classifier = NLClassifier()
        #expect(classifier.classify("please tile the windows") == .naturalLang)
    }

    @Test("Sentence starting with 'i want' returns .naturalLang")
    func testIWant() {
        let classifier = NLClassifier()
        #expect(classifier.classify("i want to resize the window") == .naturalLang)
    }

    @Test("Sentence starting with 'i need' returns .naturalLang")
    func testINeed() {
        let classifier = NLClassifier()
        #expect(classifier.classify("i need help with snippets") == .naturalLang)
    }

    // MARK: - Natural Language (action verbs)

    @Test("Action verb 'move' + object returns .naturalLang")
    func testActionVerbMove() {
        let classifier = NLClassifier()
        #expect(classifier.classify("move the window left") == .naturalLang)
    }

    @Test("Action verb 'show' + object returns .naturalLang")
    func testActionVerbShow() {
        let classifier = NLClassifier()
        #expect(classifier.classify("show all windows") == .naturalLang)
    }

    @Test("Action verb 'set' + object returns .naturalLang")
    func testActionVerbSet() {
        let classifier = NLClassifier()
        #expect(classifier.classify("set volume to 50") == .naturalLang)
    }

    @Test("Action verb 'create' + object returns .naturalLang")
    func testActionVerbCreate() {
        let classifier = NLClassifier()
        #expect(classifier.classify("create a new snippet") == .naturalLang)
    }

    @Test("Action verb 'open' + object returns .naturalLang")
    func testActionVerbOpen() {
        let classifier = NLClassifier()
        #expect(classifier.classify("open Safari") == .naturalLang)
    }

    @Test("Action verb 'tile' + object returns .naturalLang")
    func testActionVerbTile() {
        let classifier = NLClassifier()
        #expect(classifier.classify("tile windows left right") == .naturalLang)
    }

    @Test("Action verb 'help' + object returns .naturalLang")
    func testActionVerbHelp() {
        let classifier = NLClassifier()
        #expect(classifier.classify("help me with config") == .naturalLang)
    }

    @Test("Action verb 'explain' + object returns .naturalLang")
    func testActionVerbExplain() {
        let classifier = NLClassifier()
        #expect(classifier.classify("explain the snippet API") == .naturalLang)
    }

    // MARK: - Search Classification

    @Test("Single word returns .search")
    func testSingleWordSearch() {
        let classifier = NLClassifier()
        #expect(classifier.classify("safari") == .search)
    }

    @Test("Single word app name returns .search")
    func testSingleWordAppName() {
        let classifier = NLClassifier()
        #expect(classifier.classify("Terminal") == .search)
    }

    @Test("Filename ending in .js returns .search")
    func testFilenameJS() {
        let classifier = NLClassifier()
        #expect(classifier.classify("my-snippet.js") == .search)
    }

    @Test("Filename ending in .app returns .search")
    func testFilenameApp() {
        let classifier = NLClassifier()
        #expect(classifier.classify("Finder.app") == .search)
    }

    @Test("Multi-word filename with extension returns .search")
    func testMultiWordFilename() {
        let classifier = NLClassifier()
        #expect(classifier.classify("window tiler.js") == .search)
    }

    @Test("Two words without action verb returns .search")
    func testTwoWordsNonVerb() {
        let classifier = NLClassifier()
        #expect(classifier.classify("window tiler") == .search)
    }

    @Test("Multi-word without verbs returns .naturalLang for 3+ words")
    func testMultiWordNaturalLang() {
        let classifier = NLClassifier()
        // 3+ words that don't start with verb or question prefix still go to naturalLang
        let result = classifier.classify("this random phrase here")
        #expect(result == .naturalLang)
    }

    // MARK: - Empty Input

    @Test("Empty string returns .search")
    func testEmptyString() {
        let classifier = NLClassifier()
        #expect(classifier.classify("") == .search)
    }

    @Test("Whitespace only returns .search")
    func testWhitespaceOnly() {
        let classifier = NLClassifier()
        #expect(classifier.classify("   ") == .search)
    }

    // MARK: - setKnownCommands

    @Test("setKnownCommands updates the command set")
    func testSetKnownCommands() {
        let classifier = NLClassifier()
        classifier.setKnownCommands(["alpha"])
        #expect(classifier.classify("alpha") == .command)

        classifier.setKnownCommands(["beta"])
        #expect(classifier.classify("alpha") != .command)
        #expect(classifier.classify("beta") == .command)
    }

    @Test("setKnownCommands with empty set means no commands match")
    func testSetKnownCommandsEmpty() {
        let classifier = NLClassifier()
        classifier.setKnownCommands([])
        #expect(classifier.classify("reload") != .command)
    }
}

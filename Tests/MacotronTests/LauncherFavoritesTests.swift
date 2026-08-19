import Testing
@testable import MacotronEngine

@Suite("Launcher favorites")
struct LauncherFavoritesTests {
    @Test("toggle adds then removes, keeping order")
    func toggle() {
        var favs = LauncherFavorites()
        favs.toggle("a")
        favs.toggle("b")
        favs.toggle("a")
        #expect(favs.ids == ["b"])
        favs.toggle("a")
        #expect(favs.ids == ["b", "a"])
    }

    @Test("load drops blanks and duplicates")
    func load() {
        let favs = LauncherFavorites.load(from: ["x", "", "y", "x"] as [Any])
        #expect(favs.ids == ["x", "y"])
        #expect(favs.contains("x"))
        #expect(!favs.contains("z"))
    }
}

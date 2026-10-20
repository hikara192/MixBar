import XCTest
import MixBarLocalization

final class LocalizationTests: XCTestCase {

    func test_everyKeyExistsInBothLanguages() {
        XCTAssertEqual(LocalizationCatalog.missingKeys(in: .english), [])
        XCTAssertEqual(LocalizationCatalog.missingKeys(in: .russian), [])
    }

    func test_noEmptyStrings() {
        for language in ResolvedLanguage.allCases {
            for key in L10nKey.allCases {
                let value = LocalizationCatalog.string(key, language: language)
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               "\(key) is empty in \(language.rawValue)")
            }
        }
    }

    func test_russianIsActuallyTranslated() {
        // Brand names, units and format-only strings legitimately stay the same.
        let identicalAllowed: Set<L10nKey> = [.fakeEngineBadge, .mutedValue, .unmutedValue]
        for key in L10nKey.allCases where !identicalAllowed.contains(key) {
            let en = LocalizationCatalog.string(key, language: .english)
            let ru = LocalizationCatalog.string(key, language: .russian)
            XCTAssertNotEqual(en, ru, "\(key) is not translated")
        }
    }

    func test_formatSpecifiersMatch() {
        for key in L10nKey.allCases {
            let en = LocalizationCatalog.string(key, language: .english)
            let ru = LocalizationCatalog.string(key, language: .russian)
            XCTAssertEqual(formatSpecifiers(in: en), formatSpecifiers(in: ru),
                           "\(key) has mismatched format specifiers")
        }
    }

    func test_systemLanguageResolution() {
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["ru-RU", "en-US"]), .russian)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["ru"]), .russian)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["en-US"]), .english)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["de-DE"]), .english)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: []), .english)
        XCTAssertEqual(AppLanguage.english.resolved(preferredLanguages: ["ru-RU"]), .english)
        XCTAssertEqual(AppLanguage.russian.resolved(preferredLanguages: ["en-US"]), .russian)
    }

    @MainActor
    func test_storePersistsSelection() throws {
        let suite = "mixbar-localization-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = LocalizationStore(defaults: defaults)
        XCTAssertEqual(store.language, .system)
        store.language = .russian
        XCTAssertEqual(store.resolvedLanguage, .russian)
        XCTAssertEqual(store.t(.tabAbout), "О программе")

        let reloaded = LocalizationStore(defaults: defaults)
        XCTAssertEqual(reloaded.language, .russian)
        XCTAssertEqual(reloaded.t(.tabAudio), "Звук")
    }

    private func formatSpecifiers(in string: String) -> [String] {
        var result: [String] = []
        var searchRange = string.startIndex..<string.endIndex
        while let range = string.range(of: "%@", range: searchRange) {
            result.append("%@")
            searchRange = range.upperBound..<string.endIndex
        }
        return result
    }
}

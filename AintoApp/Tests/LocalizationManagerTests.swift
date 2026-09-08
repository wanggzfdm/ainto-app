import XCTest
import Combine
@testable import AintoApp

final class LocalizationManagerTests: XCTestCase {
    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "LocalizationManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    @MainActor
    func testSimplifiedChineseIdentifiersUseChinese() {
        for identifier in ["zh-Hans", "zh-CN", "zh-Hans-CN"] {
            XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: [identifier]), .simplifiedChinese)
        }
    }

    @MainActor
    func testTraditionalChineseAndOtherLanguagesUseEnglish() {
        for identifier in ["zh-Hant", "zh-TW", "en-US", "ja-JP"] {
            XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: [identifier]), .english)
        }
    }

    @MainActor
    func testSavedSelectionOverridesSystemDefault() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(AppLanguage.english.rawValue, forKey: LocalizationManager.storageKey)

        let manager = LocalizationManager(defaults: defaults, preferredLanguages: ["zh-Hans"])

        XCTAssertEqual(manager.language, .english)
    }

    @MainActor
    func testChangingLanguagePersistsAndPublishes() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = LocalizationManager(defaults: defaults, preferredLanguages: ["en-US"])
        let expectation = expectation(description: "language changed")
        let cancellable = manager.$language.dropFirst().sink { language in
            XCTAssertEqual(language, .simplifiedChinese)
            expectation.fulfill()
        }

        manager.language = .simplifiedChinese

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(defaults.string(forKey: LocalizationManager.storageKey), AppLanguage.simplifiedChinese.rawValue)
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testMissingChineseTranslationFallsBackToEnglish() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = LocalizationManager(defaults: defaults, preferredLanguages: ["zh-Hans"])

        XCTAssertEqual(manager.text("test.englishOnly"), "English fallback")
    }

    @MainActor
    func testKnownKeysReturnCurrentLanguage() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = LocalizationManager(defaults: defaults, preferredLanguages: ["en-US"])
        XCTAssertEqual(manager.text("settings.language"), "Language")

        manager.language = .simplifiedChinese
        XCTAssertEqual(manager.text("settings.language"), "语言")
    }
}

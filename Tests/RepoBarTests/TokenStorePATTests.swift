import Foundation
@testable import RepoBarCore
import Testing

struct TokenStorePATTests {
    @Test
    func savePATAndLoad() throws {
        let service = "com.johnlarkin.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        let pat = "ghp_test123456789"
        try store.savePAT(pat)

        let loaded = try store.loadPAT()
        #expect(loaded == pat)
    }

    @Test
    func clearRemovesPAT() throws {
        let service = "com.johnlarkin.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        let pat = "ghp_test123456789"
        try store.savePAT(pat)

        store.clearPAT()

        let loaded = try store.loadPAT()
        #expect(loaded == nil)
    }

    @Test
    func loadPATWhenNoneStored() throws {
        let service = "com.johnlarkin.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        let loaded = try store.loadPAT()
        #expect(loaded == nil)
    }

    @Test
    func clearAlsoClearsPAT() throws {
        let service = "com.johnlarkin.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        let pat = "ghp_test123456789"
        try store.savePAT(pat)

        // clear() should also clear PAT
        store.clear()

        let loaded = try store.loadPAT()
        #expect(loaded == nil)
    }

    @Test
    func savePATOverwritesPrevious() throws {
        let service = "com.johnlarkin.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        try store.savePAT("ghp_first")
        try store.savePAT("ghp_second")

        let loaded = try store.loadPAT()
        #expect(loaded == "ghp_second")
    }
}

import XCTest
import ProfilesCore

final class BadgePreviewTests: XCTestCase {

    // MARK: slugify (mirrors cmd_create: lowercase, keep [a-z0-9])

    func testSlugifyLowercasesAndStripsNonAlnum() {
        XCTAssertEqual(BadgePreview.slugify("Marketing"), "marketing")
        XCTAssertEqual(BadgePreview.slugify("Client X"), "clientx")
        XCTAssertEqual(BadgePreview.slugify("Work 2"), "work2")
        XCTAssertEqual(BadgePreview.slugify("My-Cool_Account!"), "mycoolaccount")
        XCTAssertEqual(BadgePreview.slugify("  Spaces  "), "spaces")
        XCTAssertEqual(BadgePreview.slugify("ünïcodé"), "ncod")   // non-ASCII dropped, like `tr -cd`
        XCTAssertEqual(BadgePreview.slugify("!!!"), "")            // engine would `err` here
    }

    // MARK: initial (mirrors badge_icon's letter derivation)

    func testInitialStripsClaudePrefixAndUppercases() {
        XCTAssertEqual(BadgePreview.initial(forName: "Marketing"), "M")
        XCTAssertEqual(BadgePreview.initial(forName: "Claude Research"), "R")
        XCTAssertEqual(BadgePreview.initial(forName: "client x"), "C")
        XCTAssertEqual(BadgePreview.initial(forName: ""), "C")     // engine falls back to "C"
        XCTAssertEqual(BadgePreview.initial(forName: "  "), "C")
    }

    // MARK: cksum — exact POSIX ground truth (verified against `printf '%s' <slug> | cksum`)

    func testCksumMatchesPOSIX() {
        XCTAssertEqual(BadgePreview.cksum(Array("business".utf8)), 952501230)
        XCTAssertEqual(BadgePreview.cksum(Array("research".utf8)), 2623492576)
        XCTAssertEqual(BadgePreview.cksum(Array("clientx".utf8)), 1122994221)
        XCTAssertEqual(BadgePreview.cksum(Array("marketing".utf8)), 1672030520)
        XCTAssertEqual(BadgePreview.cksum(Array("work".utf8)), 2243197114)
        XCTAssertEqual(BadgePreview.cksum(Array("work2".utf8)), 3114731574)
        XCTAssertEqual(BadgePreview.cksum(Array("teal".utf8)), 863970173)
        XCTAssertEqual(BadgePreview.cksum(Array("a".utf8)), 1220704766)
    }

    // MARK: badge color index — cksum % 6, matching engine badge_index_for

    func testBadgeColorIndexMatchesEngine() {
        XCTAssertEqual(BadgePreview.badgeColorIndex(forSlug: "business"), 0)   // blue
        XCTAssertEqual(BadgePreview.badgeColorIndex(forSlug: "research"), 4)   // pink
        XCTAssertEqual(BadgePreview.badgeColorIndex(forSlug: "clientx"), 3)    // purple
        XCTAssertEqual(BadgePreview.badgeColorIndex(forSlug: "marketing"), 2)  // amber
        XCTAssertEqual(BadgePreview.badgeColorIndex(forSlug: "work"), 4)
        XCTAssertEqual(BadgePreview.badgeColorIndex(forSlug: "work2"), 0)
    }

    func testBadgeColorIndexIsDeterministicAndInRange() {
        for name in ["alpha", "beta", "gamma", "Some Long Name 42", "z"] {
            let slug = BadgePreview.slugify(name)
            let i1 = BadgePreview.badgeColorIndex(forSlug: slug)
            let i2 = BadgePreview.badgeColorIndex(forSlug: slug)
            XCTAssertEqual(i1, i2)                     // deterministic
            XCTAssertTrue(i1 >= 0 && i1 < 6)           // in palette range
        }
    }

    static let allTests: [(String, (BadgePreviewTests) -> () async throws -> Void)] = [
        ("testSlugifyLowercasesAndStripsNonAlnum", testSlugifyLowercasesAndStripsNonAlnum),
        ("testInitialStripsClaudePrefixAndUppercases", testInitialStripsClaudePrefixAndUppercases),
        ("testCksumMatchesPOSIX", testCksumMatchesPOSIX),
        ("testBadgeColorIndexMatchesEngine", testBadgeColorIndexMatchesEngine),
        ("testBadgeColorIndexIsDeterministicAndInRange", testBadgeColorIndexIsDeterministicAndInRange),
    ]
}

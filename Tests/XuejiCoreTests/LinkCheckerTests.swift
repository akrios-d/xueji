import XCTest
@testable import XuejiCore

final class LinkCheckerTests: XCTestCase {
    private let list = """
    1. 阎学通：《世界权力的转移：政治领导与战略竞争》，北京大学出版社，2015 年版，第3-34 页。
    2. Craig Kafura & Dina Smeltz, “Cooperation, Competition, or Confrontation?,” The Council Global Affairs, December 2021, https://globalaffairs.org/sites/default/files/2021-12/Final%20China%20Brief.pdf, 访问时间：2024 年 7 月 1 日。
    3. Gupta, S. (2019). Indian foreign policy under Modi. International Studies Perspectives, 20(1), 1-45. https://doi.org/10.1093/isp/ekz001
    """

    func testOnlyReferencesWithALinkOrDOIAreOnline() {
        let found = LinkExtractor.links(in: list)
        XCTAssertEqual(found.online.map(\.number), [2, 3])
        XCTAssertEqual(found.offline, 1)
        XCTAssertEqual(found.online[1].url.host, "doi.org")
    }

    func testADOIWithoutALinkBecomesADOIAddress() {
        let found = LinkExtractor.links(in: "1. Gupta, S. (2019). A title. Journal. DOI: 10.1093/isp/ekz001")
        XCTAssertEqual(found.online.first?.url.absoluteString, "https://doi.org/10.1093/isp/ekz001")
    }

    func testStatusesAreClassified() async {
        let url = URL(string: "https://example.org/a")!
        let ok = await LinkChecker { _, _ in 200 }.check(url)
        let gone = await LinkChecker { _, _ in 404 }.check(url)
        let blocked = await LinkChecker { _, _ in 403 }.check(url)
        let down = await LinkChecker { _, _ in throw URLError(.cannotFindHost) }.check(url)
        XCTAssertEqual(ok, .ok(200))
        XCTAssertEqual(gone, .broken(404))
        XCTAssertEqual(blocked, .blocked(403))
        XCTAssertEqual(down, .unreachable)
        XCTAssertTrue(ok.isDone)
        XCTAssertFalse(blocked.isDone)
    }

    func testAPageThatRefusesHeadButOpensWithGetIsOK() async {
        let status = await LinkChecker { _, method in method == "HEAD" ? 405 : 200 }.check(URL(string: "https://example.org")!)
        XCTAssertEqual(status, .ok(200))
    }
}

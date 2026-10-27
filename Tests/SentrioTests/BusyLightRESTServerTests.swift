import Darwin
import Foundation
@testable import SentrioCore
import XCTest

final class BusyLightRESTServerTests: XCTestCase {
    func test_responseBodyIsFullyDeliveredBeforeConnectionCloses() throws {
        let expectedBody = Data(repeating: 0x41, count: 32 * 1024)
        let server = BusyLightRESTServer { _ in
            BusyLightRESTResponse(
                statusCode: 200,
                contentType: "application/octet-stream",
                body: expectedBody
            )
        }
        defer { server.stop() }

        let ready = expectation(description: "REST server ready")
        server.onStateChange = { running, error in
            XCTAssertNil(error)
            if running {
                ready.fulfill()
            }
        }

        let port = unusedLocalPort()
        server.start(port: port)
        wait(for: [ready], timeout: 2)

        let responseReceived = expectation(description: "complete HTTP response")
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/busylight/state"))
        URLSession.shared.dataTask(with: url) { data, response, error in
            XCTAssertNil(error)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            XCTAssertEqual(data, expectedBody)
            responseReceived.fulfill()
        }.resume()

        wait(for: [responseReceived], timeout: 2)
    }

    func test_crossSiteBrowserRequestIsRejectedBeforeHandling() throws {
        let handlerCalled = expectation(description: "request handler not called")
        handlerCalled.isInverted = true
        let server = BusyLightRESTServer { _ in
            handlerCalled.fulfill()
            return .text(statusCode: 200, body: "changed")
        }
        defer { server.stop() }

        let ready = expectation(description: "REST server ready")
        server.onStateChange = { running, error in
            XCTAssertNil(error)
            if running {
                ready.fulfill()
            }
        }

        let port = unusedLocalPort()
        server.start(port: port)
        wait(for: [ready], timeout: 2)

        let responseReceived = expectation(description: "cross-site response")
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/busylight/red"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("https://example.com", forHTTPHeaderField: "Origin")
        request.setValue("cross-site", forHTTPHeaderField: "Sec-Fetch-Site")
        request.httpBody = Data("Origin: http://127.0.0.1\r\nSec-Fetch-Site: none".utf8)
        URLSession.shared.dataTask(with: request) { _, response, error in
            XCTAssertNil(error)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 403)
            responseReceived.fulfill()
        }.resume()

        wait(for: [responseReceived, handlerCalled], timeout: 0.3)
    }

    private func unusedLocalPort() -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(bindResult, 0)

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        XCTAssertEqual(nameResult, 0)
        return Int(UInt16(bigEndian: address.sin_port))
    }
}

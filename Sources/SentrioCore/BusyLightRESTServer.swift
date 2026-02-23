import Foundation
import Network

struct BusyLightRESTRequest {
    var method: String
    var path: String
}

struct BusyLightRESTResponse {
    var statusCode: Int
    var contentType: String
    var body: Data

    static func json(statusCode: Int, object: some Encodable) -> BusyLightRESTResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(object)) ?? Data("{}".utf8)
        return BusyLightRESTResponse(statusCode: statusCode, contentType: "application/json; charset=utf-8", body: data)
    }

    static func text(statusCode: Int, body: String) -> BusyLightRESTResponse {
        BusyLightRESTResponse(statusCode: statusCode, contentType: "text/plain; charset=utf-8", body: Data(body.utf8))
    }
}

final class BusyLightRESTServer {
    var onStateChange: ((Bool, String?) -> Void)?

    private let requestHandler: (BusyLightRESTRequest) -> BusyLightRESTResponse
    private let queue = DispatchQueue(label: "Sentrio.BusyLightRESTServer")
    private var listener: NWListener?

    init(requestHandler: @escaping (BusyLightRESTRequest) -> BusyLightRESTResponse) {
        self.requestHandler = requestHandler
    }

    func start(port: Int) {
        stop()

        guard (1 ... 65535).contains(port), let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            notifyState(running: false, error: "Invalid port \(port)")
            return
        }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            let listener = try NWListener(using: parameters, on: nwPort)
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    notifyState(running: true, error: nil)
                case let .failed(error):
                    notifyState(running: false, error: error.localizedDescription)
                    stop()
                case .cancelled:
                    notifyState(running: false, error: nil)
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }

            self.listener = listener
            listener.start(queue: queue)
        } catch {
            notifyState(running: false, error: error.localizedDescription)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(connection: NWConnection) {
        guard isLoopback(connection.endpoint) else {
            connection.cancel()
            return
        }

        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                connection.cancel()
                return
            }

            var buffer = accumulated
            if let data { buffer.append(data) }

            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil || isComplete {
                processRequestData(buffer, on: connection)
                return
            }

            if buffer.count > 64 * 1024 {
                send(
                    BusyLightRESTResponse.text(statusCode: 413, body: "Request too large"),
                    on: connection
                )
                return
            }

            receiveRequest(on: connection, accumulated: buffer)
        }
    }

    private func processRequestData(_ data: Data, on connection: NWConnection) {
        guard
            let requestText = String(data: data, encoding: .utf8),
            let firstLine = requestText.components(separatedBy: "\r\n").first
        else {
            send(BusyLightRESTResponse.text(statusCode: 400, body: "Malformed request"), on: connection)
            return
        }

        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            send(BusyLightRESTResponse.text(statusCode: 400, body: "Malformed request line"), on: connection)
            return
        }

        let method = String(parts[0])
        let target = String(parts[1])
        let path = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "/"

        let request = BusyLightRESTRequest(method: method, path: path)
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                connection.cancel()
                return
            }
            let response = requestHandler(request)
            send(response, on: connection)
        }
    }

    private func send(_ response: BusyLightRESTResponse, on connection: NWConnection) {
        let header = """
        HTTP/1.1 \(response.statusCode) \(statusText(for: response.statusCode))\r
        Content-Type: \(response.contentType)\r
        Content-Length: \(response.body.count)\r
        Connection: close\r
        \r
        """
        var payload = Data(header.utf8)
        payload.append(response.body)

        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func notifyState(running: Bool, error: String?) {
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(running, error)
        }
    }

    private func statusText(for code: Int) -> String {
        switch code {
        case 200: "OK"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 413: "Payload Too Large"
        case 500: "Internal Server Error"
        case 503: "Service Unavailable"
        default: "Status"
        }
    }

    private func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        let value = host.debugDescription.lowercased()
        return value == "127.0.0.1" || value == "::1" || value == "localhost"
    }
}

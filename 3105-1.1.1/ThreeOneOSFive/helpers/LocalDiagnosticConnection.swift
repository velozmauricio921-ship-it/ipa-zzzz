import Combine
import Foundation
import Network

enum LocalDiagnosticFrameError: LocalizedError {
    case payloadTooLarge

    var errorDescription: String? {
        switch self {
        case .payloadTooLarge:
            return "El payload supera el tamaño representable en el encabezado de 4 bytes."
        }
    }
}

enum LocalDiagnosticFrameCodec {
    static func encode(_ message: [String: Any]) throws -> Data {
        let plist = try PropertyListSerialization.data(
            fromPropertyList: message,
            format: .binary,
            options: 0
        )
        guard let payloadLength = UInt32(exactly: plist.count) else {
            throw LocalDiagnosticFrameError.payloadTooLarge
        }

        var networkLength = payloadLength.bigEndian
        var frame = Data()
        frame.reserveCapacity(MemoryLayout<UInt32>.size + plist.count)
        Swift.withUnsafeBytes(of: &networkLength) { headerBytes in
            frame.append(contentsOf: headerBytes)
        }
        frame.append(plist)
        return frame
    }
}

@MainActor
final class LocalDiagnosticConnection: ObservableObject {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    @Published private(set) var state: State = .disconnected

    var statusText: String {
        switch state {
        case .disconnected:
            return "Desconectado"
        case .connecting:
            return "Conectando..."
        case .connected:
            return "Conectado"
        case .failed(let message):
            return "Error: \(message)"
        }
    }

    private let port: NWEndpoint.Port
    private let probe: Data
    private let expectedResponse: Data
    private let timeout: TimeInterval
    private var connection: NWConnection?
    private var timeoutTask: Task<Void, Never>?
    private var attemptID = UUID()

    init?(port: UInt16, probe: Data, expectedResponse: Data, timeout: TimeInterval = 5) {
        guard let endpointPort = NWEndpoint.Port(rawValue: port),
              !probe.isEmpty,
              !expectedResponse.isEmpty,
              timeout > 0 else {
            return nil
        }

        self.port = endpointPort
        self.probe = probe
        self.expectedResponse = expectedResponse
        self.timeout = timeout
    }

    func connect() {
        disconnect()
        let currentAttempt = UUID()
        attemptID = currentAttempt
        state = .connecting

        let connection = NWConnection(
            to: .hostPort(host: NWEndpoint.Host("127.0.0.1"), port: port),
            using: .tcp
        )
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor [weak self] in
                guard let self, self.attemptID == currentAttempt else { return }
                switch newState {
                case .ready:
                    self.sendProbe(on: connection, attemptID: currentAttempt)
                case .failed(let error):
                    self.fail(error.localizedDescription, attemptID: currentAttempt)
                case .cancelled:
                    break
                default:
                    break
                }
            }
        }

        connection.start(queue: .global(qos: .utility))
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            await self?.fail("Tiempo de espera agotado", attemptID: currentAttempt)
        }
    }

    func disconnect() {
        attemptID = UUID()
        timeoutTask?.cancel()
        timeoutTask = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        state = .disconnected
    }

    private func sendProbe(on connection: NWConnection, attemptID: UUID) {
        let expectedResponse = expectedResponse
        connection.send(content: probe, completion: .contentProcessed { [weak self] error in
            if let error {
                Task { @MainActor [weak self] in
                    self?.fail(error.localizedDescription, attemptID: attemptID)
                }
                return
            }
            connection.receive(
                minimumIncompleteLength: expectedResponse.count,
                maximumLength: expectedResponse.count
            ) { [weak self] data, _, isComplete, receiveError in
                Task { @MainActor [weak self] in
                    guard let self, self.attemptID == attemptID else { return }
                    if let receiveError {
                        self.fail(receiveError.localizedDescription, attemptID: attemptID)
                    } else if let data,
                              data.count == expectedResponse.count,
                              data == expectedResponse {
                        self.timeoutTask?.cancel()
                        self.timeoutTask = nil
                        self.state = .connected
                    } else if isComplete || data != nil {
                        self.fail("Respuesta de enlace no válida", attemptID: attemptID)
                    }
                }
            }
        })
    }

    private func fail(_ message: String, attemptID: UUID) {
        guard self.attemptID == attemptID else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        state = .failed(message)
    }
}
import Foundation

enum KeyAuthLicenseState: String {
    case valid = "valid"
    case invalid = "invalid"
    case expired = "expired"
    case used = "used"
    case unknown = "unknown"

    var summary: String {
        switch self {
        case .valid: return "licencia válida"
        case .invalid: return "licencia inválida"
        case .expired: return "licencia expirada"
        case .used: return "licencia en uso"
        case .unknown: return "estado desconocido"
        }
    }
}

enum KeyAuthLicenseError: LocalizedError {
    case emptyLicense
    case invalidConfiguration
    case badResponse
    case requestFailed(Int)
    case requestFailedWithBody(Int, String?)
    case decodingFailed(String?)
    case initFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyLicense:
            return "Ingresa una licencia válida."
        case .invalidConfiguration:
            return "Falta configurar la app de KeyAuth en KeyAuthConfig."
        case .badResponse:
            return "La respuesta de KeyAuth no fue válida."
        case .requestFailed(let statusCode):
            return "KeyAuth respondió con error HTTP \(statusCode)."
        case .requestFailedWithBody(let statusCode, let body):
            return "KeyAuth HTTP \(statusCode): \(body ?? "(sin cuerpo)")"
        case .decodingFailed(let body):
            return "No se pudo interpretar la respuesta de KeyAuth. Respuesta: \(body ?? "(sin cuerpo)")"
        case .initFailed(let msg):
            return msg
        }
    }
}

import Foundation

struct BlueSkyAuth: Codable {
    var identifier: String // handle or email
    var password: String
    var session: String?
    var refreshToken: String?
    var did: String?
    
    var isLoggedIn: Bool {
        return session != nil && session?.isEmpty == false && did != nil
    }
    
    init(identifier: String, password: String, session: String? = nil, refreshToken: String? = nil, did: String? = nil) {
        self.identifier = identifier
        self.password = password
        self.session = session
        self.refreshToken = refreshToken
        self.did = did
    }
} 
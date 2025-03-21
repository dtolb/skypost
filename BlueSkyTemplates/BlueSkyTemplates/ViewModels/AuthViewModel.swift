import Foundation
import SwiftUI

@MainActor
class AuthViewModel: ObservableObject {
    @Published var auth: BlueSkyAuth?
    @Published var isLoggedIn = false
    @Published var isLoggingIn = false
    @Published var loginError: String?
    
    private let blueSkyService = BlueSkyService()
    
    init() {
        checkLoginStatus()
    }
    
    private func checkLoginStatus() {
        isLoggedIn = blueSkyService.isAuthenticated()
    }
    
    func login(identifier: String, password: String) async {
        guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !password.isEmpty else {
            loginError = "Username and password are required"
            return
        }
        
        isLoggingIn = true
        loginError = nil
        
        let result = await blueSkyService.login(identifier: identifier, password: password)
        
        isLoggingIn = false
        
        switch result {
        case .success(let auth):
            self.auth = auth
            self.isLoggedIn = true
        case .failure(_):
            self.loginError = "Login failed. Please check your credentials."
        }
    }
    
    func logout() {
        blueSkyService.clearAuth()
        self.auth = nil
        self.isLoggedIn = false
    }
} 
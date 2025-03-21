import SwiftUI

struct LoginView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var identifier = ""
    @State private var password = ""
    @State private var isAuthenticating = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("BlueSky Login")) {
                    TextField("Username or Email", text: $identifier)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.emailAddress)
                    
                    SecureField("Password", text: $password)
                }
                
                if let error = authViewModel.loginError {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                Section {
                    Button(action: {
                        login()
                    }) {
                        if authViewModel.isLoggingIn {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Login to BlueSky")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .bold()
                        }
                    }
                    .disabled(identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || authViewModel.isLoggingIn)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Note:")
                            .font(.headline)
                        
                        Text("This app requires you to log in with your BlueSky credentials to post. Your login information is stored securely on this device only. The app communicates directly with the official BlueSky API.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 5)
                }
            }
            .navigationTitle("Login")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(authViewModel.isLoggingIn)
        }
    }
    
    private func login() {
        Task {
            await authViewModel.login(identifier: identifier, password: password)
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView(authViewModel: AuthViewModel())
    }
} 
import SwiftUI

struct ContentView: View {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var postViewModel = PostViewModel()
    
    var body: some View {
        Group {
            if authViewModel.isLoggedIn {
                CreatePostView(
                    postViewModel: postViewModel,
                    authViewModel: authViewModel
                )
            } else {
                LoginView(authViewModel: authViewModel)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
} 

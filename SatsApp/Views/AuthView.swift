import SwiftUI

struct AuthView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        if authManager.showConfirmation {
            ConfirmEmailView()
        } else {
            switch authManager.authMode {
            case .signUp:
                SignUpView()
            case .signIn:
                SignInView()
            }
        }
    }
}

struct AuthView_Previews: PreviewProvider {
    static var previews: some View {
        AuthView()
            .environmentObject(AuthManager())
    }
}
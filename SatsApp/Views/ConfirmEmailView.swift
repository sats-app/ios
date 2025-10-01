import SwiftUI

struct ConfirmEmailView: View {
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 20) {
                Text("Check Your Email")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(authManager.authMode == .signUp ? "We've sent a 6-digit confirmation code to" : "We've sent a 6-digit sign-in code to")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                if let email = authManager.userEmail {
                    Text(email)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                        .multilineTextAlignment(.center)
                }
                
                Text(authManager.authMode == .signUp ? "Enter the code below to complete your sign up" : "Enter the code below to sign in")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 16) {
                Text("Confirmation Code")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                TextField("Enter 6-digit code", text: $authManager.confirmationCode)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title2)
                    .padding(.horizontal, 40)
            }
            
            if let error = authManager.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 12) {
                Button(action: {
                    Task {
                        if authManager.authMode == .signUp {
                            await authManager.confirmSignUp()
                        } else {
                            await authManager.confirmOTP()
                        }
                    }
                }) {
                if authManager.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(10)
                } else {
                    Text("Confirm")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 40)
            .disabled(authManager.isLoading || authManager.confirmationCode.count != 6)

            Button(action: {
                Task {
                    await authManager.resendConfirmationCode()
                }
            }) {
                Text("Resend Code")
                    .font(.footnote)
                    .foregroundColor(.accentColor)
            }
            .disabled(authManager.isLoading)
            }

            Spacer()
        }
        .padding()
    }
}

struct ConfirmEmailView_Previews: PreviewProvider {
    static var previews: some View {
        ConfirmEmailView()
            .environmentObject(AuthManager())
    }
}
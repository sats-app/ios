import SwiftUI
import Amplify
import AWSCognitoAuthPlugin

struct PasswordlessAuthView: View {
    @State private var email = ""
    @State private var verificationCode = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var showVerification = false
    @State private var currentUsername: String?

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            VStack(spacing: 20) {
                Text("Welcome to SatsApp")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("Passwordless sign in with email")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if showVerification {
                verificationView
            } else {
                emailView
            }

            Spacer()
        }
        .padding()
    }

    var emailView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.headline)
                    .foregroundColor(.primary)

                TextField("Enter your email", text: $email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
            .padding(.horizontal, 20)

            if let error = error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }

            Button(action: {
                Task {
                    await signInWithEmailOTP()
                }
            }) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(10)
                } else {
                    Text("Continue with Email")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .disabled(isLoading || email.isEmpty)
            .padding(.horizontal, 40)
        }
    }

    var verificationView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 20) {
                Text("Check Your Email")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("We've sent a verification code to")
                    .font(.body)
                    .foregroundColor(.secondary)

                Text(email)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)

                Text("Enter the code below to sign in")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 8) {
                Text("Verification Code")
                    .font(.headline)
                    .foregroundColor(.primary)

                TextField("Enter code", text: $verificationCode)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title2)
            }
            .padding(.horizontal, 40)

            if let error = error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button(action: {
                    Task {
                        await confirmOTP()
                    }
                }) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .cornerRadius(10)
                    } else {
                        Text("Verify")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .disabled(isLoading || verificationCode.isEmpty)
                .padding(.horizontal, 40)

                Button(action: {
                    showVerification = false
                    verificationCode = ""
                    error = nil
                }) {
                    Text("Use a different email")
                        .font(.footnote)
                        .foregroundColor(.accentColor)
                }
                .disabled(isLoading)
            }
        }
    }

    @MainActor
    private func signInWithEmailOTP() async {
        isLoading = true
        error = nil
        currentUsername = email

        guard isValidEmail(email) else {
            error = "Please enter a valid email address"
            isLoading = false
            return
        }

        do {
            AppLogger.auth.debug("Initiating EMAIL_OTP sign in for: \(email)")

            let pluginOptions = AWSAuthSignInOptions(
                authFlowType: .userAuth(preferredFirstFactor: .emailOTP)
            )

            let signInResult = try await Amplify.Auth.signIn(
                username: email,
                options: .init(pluginOptions: pluginOptions)
            )

            AppLogger.auth.debug("Sign in result: \(String(describing: signInResult.nextStep))")

            isLoading = false

            switch signInResult.nextStep {
            case .continueSignInWithFirstFactorSelection(let availableFactors):
                AppLogger.auth.debug("Available factors: \(availableFactors)")
                if availableFactors.contains(.emailOTP) {
                    await selectEmailOTP()
                } else {
                    error = "Email OTP authentication is not available"
                }
            case .confirmSignInWithOTP:
                showVerification = true
            case .done:
                AppLogger.auth.info("User signed in successfully")
            default:
                error = "Unexpected sign in step"
                AppLogger.auth.warning("Unexpected step: \(String(describing: signInResult.nextStep))")
            }
        } catch {
            isLoading = false
            self.error = error.localizedDescription
            AppLogger.auth.error("Sign in failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func selectEmailOTP() async {
        isLoading = true
        error = nil

        do {
            let signInResult = try await Amplify.Auth.confirmSignIn(
                challengeResponse: "EMAIL_OTP"
            )

            isLoading = false

            switch signInResult.nextStep {
            case .confirmSignInWithOTP:
                showVerification = true
            case .done:
                AppLogger.auth.info("User signed in successfully")
            default:
                error = "Unexpected step after selecting EMAIL_OTP"
            }
        } catch {
            isLoading = false
            self.error = error.localizedDescription
            AppLogger.auth.error("Factor selection failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func confirmOTP() async {
        isLoading = true
        error = nil

        do {
            let confirmResult = try await Amplify.Auth.confirmSignIn(
                challengeResponse: verificationCode
            )

            isLoading = false

            switch confirmResult.nextStep {
            case .done:
                AppLogger.auth.info("User authenticated successfully")
            default:
                error = "Unexpected step after OTP confirmation"
            }
        } catch {
            isLoading = false
            self.error = "Invalid verification code. Please try again."
            AppLogger.auth.error("OTP confirmation failed: \(error.localizedDescription)")
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
    }
}

struct PasswordlessAuthView_Previews: PreviewProvider {
    static var previews: some View {
        PasswordlessAuthView()
    }
}

import Foundation
import Amplify
import AWSCognitoAuthPlugin

enum AuthMode {
    case signUp
    case signIn
}

class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var userEmail: String?
    @Published var username: String?
    @Published var isLoading = false
    @Published var error: String?
    @Published var showConfirmation = false
    @Published var confirmationCode = ""
    @Published var authMode: AuthMode = .signUp

    private var signUpUsername: String?

    init() {
        loadAuthState()
    }
    
    @MainActor
    func signUpPasswordless(email: String, username: String) async {
        isLoading = true
        error = nil

        // Basic validation
        guard isValidEmail(email) else {
            isLoading = false
            error = "Please enter a valid email address"
            return
        }

        guard isValidUsername(username) else {
            isLoading = false
            error = "Username must be 3-20 characters and contain only letters, numbers, and underscores"
            return
        }

        // Store email as the sign-up username
        signUpUsername = email

        let userAttributes = [
            AuthUserAttribute(.email, value: email),
            AuthUserAttribute(.preferredUsername, value: username)
        ]

        do {
            print("Starting passwordless sign up with email: \(email)")
            // For passwordless, we still need to provide a temporary password
            // This will be replaced by OTP authentication
            let tempPassword = UUID().uuidString + "Aa1!"

            let signUpResult = try await Amplify.Auth.signUp(
                username: email,
                password: tempPassword,
                options: AuthSignUpRequest.Options(userAttributes: userAttributes)
            )
            print("SignUp result received: \(signUpResult)")

            isLoading = false

            if case .confirmUser = signUpResult.nextStep {
                showConfirmation = true
                userEmail = email
                self.username = username
            } else if signUpResult.isSignUpComplete {
                // After sign up, initiate sign in with OTP
                await signInWithOTP(email: email)
            }
        } catch let error as AuthError {
            isLoading = false
            switch error {
            case .validation(let field, _, let recoverySuggestion, _):
                self.error = "Invalid \(field): \(recoverySuggestion)"
            case .service(_, let recoverySuggestion, _):
                if recoverySuggestion.contains("already exists") {
                    self.error = "An account with this email already exists. Please sign in."
                } else {
                    self.error = recoverySuggestion
                }
            default:
                self.error = "Sign up failed: \(error.errorDescription)"
            }
            print("Amplify Auth error: \(error)")
        } catch {
            isLoading = false
            self.error = "Sign up failed: \(error.localizedDescription)"
            print("Sign up error: \(error)")
        }
    }

    @MainActor
    func signInWithOTP(email: String) async {
        isLoading = true
        error = nil

        guard isValidEmail(email) else {
            isLoading = false
            error = "Please enter a valid email address"
            return
        }

        do {
            print("Initiating OTP sign in for email: \(email)")

            // Use EMAIL_OTP as preferred factor for passwordless authentication
            let pluginOptions = AWSAuthSignInOptions(
                authFlowType: .userAuth(preferredFirstFactor: .emailOTP)
            )

            let signInResult = try await Amplify.Auth.signIn(
                username: email,
                options: .init(pluginOptions: pluginOptions)
            )

            print("Sign in result: \(signInResult)")

            isLoading = false

            // Check the next step
            switch signInResult.nextStep {
            case .confirmSignInWithOTP:
                showConfirmation = true
                userEmail = email
                signUpUsername = email
            case .done:
                isAuthenticated = true
                userEmail = email
                saveAuthState()
            default:
                print("Unexpected next step: \(signInResult.nextStep)")
            }
        } catch let error as AuthError {
            isLoading = false
            self.error = "Sign in failed: \(error.errorDescription)"
            print("Sign in error: \(error)")
        } catch {
            isLoading = false
            self.error = "Sign in failed: \(error.localizedDescription)"
            print("Sign in error: \(error)")
        }
    }
    
    @MainActor
    func confirmSignUp() async {
        isLoading = true
        error = nil

        guard let email = signUpUsername else {
            error = "Email not found"
            isLoading = false
            return
        }

        do {
            print("Confirming sign up with code: \(confirmationCode) for email: \(email)")
            let confirmResult = try await Amplify.Auth.confirmSignUp(
                for: email,
                confirmationCode: confirmationCode
            )
            print("ConfirmSignUp result received: \(confirmResult)")

            isLoading = false

            if confirmResult.isSignUpComplete {
                // After confirming sign up, initiate OTP sign in
                showConfirmation = false
                await signInWithOTP(email: email)
            }
        } catch let error as AuthError {
            isLoading = false
            switch error {
            case .service(let errorMessage, let recoverySuggestion, _):
                if errorMessage.contains("CodeMismatch") {
                    self.error = "Invalid confirmation code. Please check the code and try again."
                } else if errorMessage.contains("ExpiredCode") {
                    self.error = "Confirmation code has expired. Please request a new code."
                } else {
                    self.error = recoverySuggestion
                }
            default:
                self.error = "Confirmation failed: \(error.errorDescription)"
            }
            print("Amplify Auth error: \(error)")
        } catch {
            isLoading = false
            self.error = "Confirmation failed: \(error.localizedDescription)"
            print("Confirmation error: \(error)")
        }
    }

    @MainActor
    func confirmOTP() async {
        isLoading = true
        error = nil

        do {
            print("Confirming OTP: \(confirmationCode)")
            let confirmResult = try await Amplify.Auth.confirmSignIn(
                challengeResponse: confirmationCode
            )
            print("OTP confirmation result: \(confirmResult)")

            isLoading = false

            switch confirmResult.nextStep {
            case .done:
                isAuthenticated = true
                showConfirmation = false
                saveAuthState()

                // Fetch user attributes after successful sign in
                let userAttributes = try await Amplify.Auth.fetchUserAttributes()
                for attribute in userAttributes {
                    if attribute.key == .email {
                        userEmail = attribute.value
                    } else if attribute.key == .preferredUsername {
                        username = attribute.value
                    }
                }
            default:
                print("Unexpected next step after OTP confirmation: \(confirmResult.nextStep)")
            }
        } catch let error as AuthError {
            isLoading = false
            self.error = "OTP verification failed: \(error.errorDescription)"
            print("OTP confirmation error: \(error)")
        } catch {
            isLoading = false
            self.error = "OTP verification failed: \(error.localizedDescription)"
            print("OTP confirmation error: \(error)")
        }
    }
    
    func signOut() {
        isAuthenticated = false
        userEmail = nil
        username = nil
        showConfirmation = false
        confirmationCode = ""
        signUpUsername = nil
        clearAuthState()
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
    }
    
    private func isValidUsername(_ username: String) -> Bool {
        let usernameRegEx = "^[a-zA-Z0-9_]{3,20}$"
        let usernamePred = NSPredicate(format:"SELF MATCHES %@", usernameRegEx)
        return usernamePred.evaluate(with: username)
    }
    
    @MainActor
    func resendConfirmationCode() async {
        isLoading = true
        error = nil

        guard let email = signUpUsername ?? userEmail else {
            error = "Email not found"
            isLoading = false
            return
        }

        do {
            print("Resending confirmation code to: \(email)")
            let result = try await Amplify.Auth.resendSignUpCode(for: email)
            print("Resend result: \(result)")

            isLoading = false
            error = "A new code has been sent to your email"
        } catch {
            isLoading = false
            self.error = "Failed to resend code: \(error.localizedDescription)"
            print("Resend code error: \(error)")
        }
    }
    
    private func saveAuthState() {
        UserDefaults.standard.set(isAuthenticated, forKey: "isAuthenticated")
        UserDefaults.standard.set(userEmail, forKey: "userEmail")
        UserDefaults.standard.set(username, forKey: "username")
    }
    
    private func loadAuthState() {
        isAuthenticated = UserDefaults.standard.bool(forKey: "isAuthenticated")
        userEmail = UserDefaults.standard.string(forKey: "userEmail")
        username = UserDefaults.standard.string(forKey: "username")
    }
    
    private func clearAuthState() {
        UserDefaults.standard.removeObject(forKey: "isAuthenticated")
        UserDefaults.standard.removeObject(forKey: "userEmail")
        UserDefaults.standard.removeObject(forKey: "username")
    }
}


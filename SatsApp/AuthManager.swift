import Foundation
import Amplify
import AWSCognitoAuthPlugin

class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var userEmail: String?
    @Published var username: String?
    @Published var isLoading = false
    @Published var error: String?
    @Published var showConfirmation = false
    @Published var confirmationCode = ""
    
    private let userPoolId = "us-east-2_zQ8aKO1PI"
    private let clientId = "1e7o225bcugq1bdo0kvsdccvb2"
    
    private var signUpUsername: String?
    
    init() {
        configureAmplify()
        loadAuthState()
    }
    
    private func configureAmplify() {
        do {
            let authPlugin = AWSCognitoAuthPlugin()
            try Amplify.add(plugin: authPlugin)
            
            // Use the configuration file approach
            let config = """
            {
                "auth": {
                    "plugins": {
                        "awsCognitoAuthPlugin": {
                            "UserAgent": "aws-amplify-cli/0.1.0",
                            "Version": "0.1.0",
                            "IdentityManager": {
                                "Default": {}
                            },
                            "CognitoUserPool": {
                                "Default": {
                                    "PoolId": "\(userPoolId)",
                                    "AppClientId": "\(clientId)",
                                    "Region": "us-east-2"
                                }
                            },
                            "Auth": {
                                "Default": {
                                    "authenticationFlowType": "USER_SRP_AUTH"
                                }
                            }
                        }
                    }
                }
            }
            """
            
            let configData = config.data(using: .utf8)!
            let amplifyConfig = try JSONDecoder().decode(AmplifyConfiguration.self, from: configData)
            try Amplify.configure(amplifyConfig)
            
            print("Amplify configured successfully")
        } catch {
            print("Failed to configure Amplify: \(error)")
        }
    }
    
    @MainActor
    func signUpWithPasskey(email: String, username: String) async {
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
        
        signUpUsername = username
        
        let generatedPassword = generateRandomPassword()
        print("Attempting sign up with:")
        print("- ClientId: \(clientId)")
        print("- Username: \(username)")
        print("- Email: \(email)")
        print("- Password: \(generatedPassword)")
        print("- Password length: \(generatedPassword.count)")
        
        let userAttributes = [AuthUserAttribute(.email, value: email)]
        
        do {
            print("Calling Amplify signUp...")
            let signUpResult = try await Amplify.Auth.signUp(
                username: username,
                password: generatedPassword,
                options: AuthSignUpRequest.Options(userAttributes: userAttributes)
            )
            print("SignUp result received: \(signUpResult)")
            
            isLoading = false
            
            if case .confirmUser = signUpResult.nextStep {
                showConfirmation = true
                userEmail = email
                self.username = username
            } else if signUpResult.isSignUpComplete {
                isAuthenticated = true
                userEmail = email
                self.username = username
                saveAuthState()
            }
        } catch let error as AuthError {
            isLoading = false
            switch error {
            case .validation(let field, _, let recoverySuggestion, _):
                self.error = "Invalid \(field): \(recoverySuggestion)"
            case .service(_, let recoverySuggestion, _):
                if recoverySuggestion.contains("username") {
                    self.error = "This username is already taken. Please choose a different username."
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
    func confirmSignUp() async {
        isLoading = true
        error = nil
        
        guard let username = signUpUsername else {
            error = "Username not found"
            isLoading = false
            return
        }
        
        do {
            print("Calling Amplify confirmSignUp with code: \(confirmationCode)")
            let confirmResult = try await Amplify.Auth.confirmSignUp(
                for: username,
                confirmationCode: confirmationCode
            )
            print("ConfirmSignUp result received: \(confirmResult)")
            
            isLoading = false
            
            if confirmResult.isSignUpComplete {
                isAuthenticated = true
                showConfirmation = false
                saveAuthState()
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
    
    private func generateRandomPassword() -> String {
        let lowercase = "abcdefghijklmnopqrstuvwxyz"
        let uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let numbers = "0123456789"
        let special = "!@#$%^&*()_+-=[]{}|;:,.<>?"
        
        // Ensure at least one character from each required set
        var password = ""
        password += String(lowercase.randomElement()!)
        password += String(uppercase.randomElement()!)
        password += String(numbers.randomElement()!)
        password += String(special.randomElement()!)
        
        // Fill the rest with random characters to make it 16 characters total
        let allCharsets = lowercase + uppercase + numbers + special
        for _ in 0..<12 {
            password += String(allCharsets.randomElement()!)
        }
        
        // Shuffle the password to avoid predictable patterns
        return String(password.shuffled())
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


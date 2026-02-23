import Foundation
import FirebaseAuth
import FirebaseCore
import AuthenticationServices
import CryptoKit
import GoogleSignIn
import UIKit

/// Central Firebase Authentication manager — wraps all Firebase Auth operations.
/// Handles Apple Sign-In, Google Sign-In, Email/Password, and auth state changes.
///
/// Usage:
/// - Call `signInWithApple(credential:)` from AuthView after Apple auth completes
/// - Call `signInWithGoogle()` for Google Sign-In flow
/// - Call `signUpWithEmail(...)` for new email accounts
/// - Call `signInWithEmail(...)` for returning email users
/// - Check `isAuthenticated` and `currentFirebaseUser` for auth state
/// - Call `getIDToken()` for API requests (auto-refreshes expired tokens)
@MainActor
@Observable
final class FirebaseAuthManager: @unchecked Sendable {
    static let shared = FirebaseAuthManager()

    // MARK: - Published State

    /// The current Firebase user (nil if signed out)
    var currentFirebaseUser: FirebaseAuth.User?

    /// Whether a Firebase user is currently authenticated
    var isAuthenticated: Bool { currentFirebaseUser != nil }

    /// Loading state for async operations
    var isAuthenticating: Bool = false

    /// Last error message for UI display
    var authError: String?

    // MARK: - Private

    /// The current nonce used for Apple Sign-In with Firebase (must persist between request and callback)
    private var currentNonce: String?

    /// Auth state listener handle — stored as nonisolated(unsafe) so deinit can access it
    nonisolated(unsafe) private var authStateHandle: AuthStateDidChangeListenerHandle?

    // MARK: - Init

    private init() {
        // Listen for Firebase auth state changes (sign in, sign out, token refresh)
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentFirebaseUser = user
            }
        }
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Apple Sign-In

    /// Generates the nonce needed for Apple Sign-In requests.
    /// Call this BEFORE presenting `ASAuthorizationController` to set the nonce on the request.
    func prepareAppleSignInNonce() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return sha256(nonce)
    }

    /// Signs in with Apple via Firebase using the credential from ASAuthorizationController.
    /// The `currentNonce` must have been set via `prepareAppleSignInNonce()` before this call.
    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws -> AuthDataResult {
        guard let nonce = currentNonce else {
            throw FirebaseAuthError.missingNonce
        }

        guard let appleIDToken = credential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            throw FirebaseAuthError.missingIdentityToken
        }

        let oauthCredential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: credential.fullName
        )

        isAuthenticating = true
        authError = nil
        defer { isAuthenticating = false }

        do {
            let result = try await Auth.auth().signIn(with: oauthCredential)
            currentNonce = nil  // Clear used nonce

            // Update display name from Apple if provided (Apple only sends name on first sign-in)
            if let fullName = credential.fullName {
                let displayName = [fullName.givenName, fullName.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                if !displayName.isEmpty, result.user.displayName == nil {
                    let changeRequest = result.user.createProfileChangeRequest()
                    changeRequest.displayName = displayName
                    try? await changeRequest.commitChanges()
                }
            }

            return result
        } catch {
            authError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Google Sign-In

    /// Signs in with Google via Firebase.
    /// Presents the Google Sign-In flow and exchanges the credential with Firebase.
    ///
    /// **Important**: Google Sign-In must be enabled in Firebase Console → Authentication → Sign-in Methods.
    /// The SDK throws ObjC NSExceptions for configuration errors (missing clientID, etc.) which bypass
    /// Swift's do/catch. We wrap the call with `ObjCExceptionCatcher` to prevent SIGABRT crashes.
    func signInWithGoogle() async throws -> AuthDataResult {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw FirebaseAuthError.missingGoogleClientID
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        // Get the top-most view controller for presenting the Google sign-in sheet
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            throw FirebaseAuthError.missingRootViewController
        }

        // Find the actual top VC (could be presented modally)
        let topVC = Self.topViewController(from: rootVC)

        isAuthenticating = true
        authError = nil
        defer { isAuthenticating = false }

        // GIDSignIn throws ObjC NSExceptions for configuration errors, which bypass Swift's
        // do/catch entirely and cause SIGABRT. We use ObjCExceptionCatcher to intercept them.
        //
        // We extract the Sendable token strings inside the callback to avoid sending
        // non-Sendable GIDSignInResult across isolation boundaries.
        //
        // IMPORTANT: Use a flag to prevent double continuation resume — if ObjC catches an
        // exception AND the GIDSignIn callback fires, resuming twice would crash.
        struct GoogleTokens: Sendable {
            let idToken: String
            let accessToken: String
        }

        // Sendable flag to prevent double continuation resume — if ObjC catches an
        // exception AND the GIDSignIn callback fires, resuming twice would crash.
        final class ResumeGuard: @unchecked Sendable {
            private var _resumed = false
            /// Returns `true` if this is the FIRST call; `false` on subsequent calls.
            func tryResume() -> Bool {
                if _resumed { return false }
                _resumed = true
                return true
            }
        }

        let tokens: GoogleTokens = try await withCheckedThrowingContinuation { continuation in
            let guard_ = ResumeGuard()

            let exceptionMessage = ObjCExceptionCatcher.catchException {
                GIDSignIn.sharedInstance.signIn(withPresenting: topVC) { result, error in
                    guard guard_.tryResume() else { return }

                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let result,
                          let idToken = result.user.idToken?.tokenString else {
                        continuation.resume(throwing: FirebaseAuthError.missingGoogleIDToken)
                        return
                    }

                    let tokens = GoogleTokens(
                        idToken: idToken,
                        accessToken: result.user.accessToken.tokenString
                    )
                    continuation.resume(returning: tokens)
                }
            }

            // If ObjC exception was caught, resume with our own error instead of crashing
            if let message = exceptionMessage {
                guard guard_.tryResume() else { return }
                continuation.resume(throwing: FirebaseAuthError.googleConfigurationError(message))
            }
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: tokens.idToken,
            accessToken: tokens.accessToken
        )

        do {
            let authResult = try await Auth.auth().signIn(with: credential)
            return authResult
        } catch let error as GIDSignInError where error.code == .canceled {
            throw FirebaseAuthError.cancelled
        } catch {
            authError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Email/Password

    /// Creates a new Firebase account with email and password, then sends verification email.
    func signUpWithEmail(email: String, password: String, firstName: String, lastName: String) async throws -> AuthDataResult {
        isAuthenticating = true
        authError = nil
        defer { isAuthenticating = false }

        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)

            // Set display name
            let displayName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            if !displayName.isEmpty {
                let changeRequest = result.user.createProfileChangeRequest()
                changeRequest.displayName = displayName
                try? await changeRequest.commitChanges()
            }

            // Send email verification — non-critical, don't let it block signup
            do {
                try await result.user.sendEmailVerification()
            } catch {
                #if DEBUG
                print("⚠️ Initial verification email failed: \(error.localizedDescription)")
                #endif
                // User can resend from ProfileView if initial send fails
            }

            return result
        } catch {
            authError = Self.friendlyErrorMessage(for: error)
            throw error
        }
    }

    /// Signs in an existing user with email and password.
    func signInWithEmail(email: String, password: String) async throws -> AuthDataResult {
        isAuthenticating = true
        authError = nil
        defer { isAuthenticating = false }

        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            return result
        } catch {
            authError = Self.friendlyErrorMessage(for: error)
            throw error
        }
    }

    // MARK: - Email Verification & Password Reset

    /// Sends (or re-sends) email verification to the current user.
    func sendEmailVerification() async throws {
        guard let user = Auth.auth().currentUser else {
            throw FirebaseAuthError.noCurrentUser
        }
        try await user.sendEmailVerification()
    }

    /// Sends a password reset email to the specified address.
    func sendPasswordReset(email: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            authError = Self.friendlyErrorMessage(for: error)
            throw error
        }
    }

    /// Whether the current user's email is verified (relevant for email/password accounts).
    var isEmailVerified: Bool {
        Auth.auth().currentUser?.isEmailVerified ?? false
    }

    /// Refreshes the current user's data from Firebase (to pick up email verification changes).
    func reloadCurrentUser() async throws {
        try await Auth.auth().currentUser?.reload()
        currentFirebaseUser = Auth.auth().currentUser
    }

    // MARK: - Token Management

    /// Gets a valid Firebase ID token for API requests.
    /// Firebase SDK automatically refreshes expired tokens (1-hour lifespan).
    func getIDToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw FirebaseAuthError.noCurrentUser
        }
        return try await user.getIDToken()
    }

    // MARK: - Sign Out & Delete

    /// Signs out the current Firebase user.
    func signOut() throws {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()  // Also sign out Google
            currentFirebaseUser = nil
            authError = nil
        } catch {
            authError = error.localizedDescription
            throw error
        }
    }

    /// Permanently deletes the current Firebase account.
    /// The user may need to re-authenticate if their session is too old.
    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            throw FirebaseAuthError.noCurrentUser
        }

        do {
            try await user.delete()
            GIDSignIn.sharedInstance.signOut()
            currentFirebaseUser = nil
        } catch {
            authError = Self.friendlyErrorMessage(for: error)
            throw error
        }
    }

    // MARK: - Helpers

    /// Generates a random nonce string for Apple Sign-In security.
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            // Fallback: use UUID-based randomness instead of crashing
            // This is less cryptographically ideal but won't kill the app
            let fallback = UUID().uuidString + UUID().uuidString
            return String(fallback.prefix(length))
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    /// SHA-256 hash of a string (used for Apple Sign-In nonce).
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Walks the view controller hierarchy to find the topmost presented VC.
    private static func topViewController(from vc: UIViewController) -> UIViewController {
        if let presented = vc.presentedViewController {
            return topViewController(from: presented)
        }
        if let nav = vc as? UINavigationController, let visible = nav.visibleViewController {
            return topViewController(from: visible)
        }
        if let tab = vc as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(from: selected)
        }
        return vc
    }

    /// Converts Firebase AuthErrorCode to user-friendly messages.
    private static func friendlyErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == AuthErrors.domain else {
            return error.localizedDescription
        }

        switch AuthErrorCode(rawValue: nsError.code) {
        case .emailAlreadyInUse:
            return "An account with this email already exists. Try signing in instead."
        case .weakPassword:
            return "Password must be at least 8 characters long."
        case .invalidEmail:
            return "Please enter a valid email address."
        case .wrongPassword, .invalidCredential:
            return "Incorrect email or password. Please try again."
        case .userNotFound:
            return "No account found with this email. Try creating one instead."
        case .tooManyRequests:
            return "Too many attempts. Please wait a moment and try again."
        case .networkError:
            return "Network error. Check your connection and try again."
        case .userDisabled:
            return "This account has been disabled. Contact support for help."
        case .requiresRecentLogin:
            return "Please sign in again to complete this action."
        default:
            return error.localizedDescription
        }
    }
}

// MARK: - Firebase Auth Errors

enum FirebaseAuthError: LocalizedError, Equatable {
    case missingNonce
    case missingIdentityToken
    case missingGoogleClientID
    case missingGoogleIDToken
    case missingRootViewController
    case noCurrentUser
    case cancelled
    case googleConfigurationError(String)

    var errorDescription: String? {
        switch self {
        case .missingNonce:
            return "Sign-in security error. Please try again."
        case .missingIdentityToken:
            return "Could not verify your Apple ID. Please try again."
        case .missingGoogleClientID:
            return "Google Sign-In is not configured. Check GoogleService-Info.plist."
        case .missingGoogleIDToken:
            return "Could not verify your Google account. Please try again."
        case .missingRootViewController:
            return "Cannot present sign-in. Please try again."
        case .noCurrentUser:
            return "You must be signed in to perform this action."
        case .cancelled:
            return nil  // User cancelled — no error to show
        case .googleConfigurationError:
            return "Google Sign-In isn't available right now. Please try another sign-in method."
        }
    }
}

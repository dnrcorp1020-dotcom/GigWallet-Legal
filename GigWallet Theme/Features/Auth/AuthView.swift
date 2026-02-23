import SwiftUI
import SwiftData
import AuthenticationServices

/// The authentication screen — shown before onboarding or when user taps "Sign In"
/// Supports: Sign in with Apple, Sign in with Google, Email/Password, and Skip
struct AuthView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Query private var profiles: [UserProfile]

    @State private var showingEmailRegistration = false
    @State private var showingEmailSignIn = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let authManager = FirebaseAuthManager.shared

    let onComplete: () -> Void

    var body: some View {
        ZStack {
            // Background: brand orange gradient
            LinearGradient(
                colors: [
                    BrandColors.primaryLight,
                    BrandColors.primary,
                    BrandColors.primaryDark
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo & branding
                VStack(spacing: Spacing.lg) {
                    // Wallet icon on white circle
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 120, height: 120)

                        Circle()
                            .fill(.white)
                            .frame(width: 96, height: 96)

                        Image(systemName: "wallet.bifold.fill")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(BrandColors.primary)
                    }

                    VStack(spacing: Spacing.sm) {
                        (Text("Gig")
                            .foregroundStyle(.white)
                        + Text("Wallet")
                            .foregroundStyle(.white.opacity(0.85)))
                            .font(.system(size: 36, weight: .bold, design: .rounded))

                        Text("Your Financial Command Center")
                            .font(Typography.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }

                Spacer()

                // Auth buttons
                VStack(spacing: Spacing.md) {
                    if let errorMessage {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 16))
                            Text(errorMessage)
                                .font(Typography.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(.ultraThinMaterial.opacity(0.8))
                        .background(BrandColors.destructive.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
                        .padding(.horizontal, Spacing.lg)
                        .multilineTextAlignment(.center)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onTapGesture {
                            withAnimation { self.errorMessage = nil }
                        }
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                                withAnimation(.easeOut(duration: 0.3)) { self.errorMessage = nil }
                            }
                        }
                    }

                    // Sign in with Apple (Firebase-backed)
                    SignInWithAppleButton(.signIn) { request in
                        let hashedNonce = authManager.prepareAppleSignInNonce()
                        request.requestedScopes = [.email, .fullName]
                        request.nonce = hashedNonce
                    } onCompletion: { result in
                        handleAppleSignIn(result: result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
                    .padding(.horizontal, Spacing.xxl)

                    // Sign in with Google (Firebase-backed)
                    Button {
                        handleGoogleSignIn()
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "g.circle.fill")
                                .font(.system(size: 20))
                            Text("Sign in with Google")
                                .font(.system(.body, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(.white)
                        .foregroundStyle(.black.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
                    }
                    .padding(.horizontal, Spacing.xxl)

                    // Email registration
                    Button {
                        showingEmailRegistration = true
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 20))
                            Text("Create Account with Email")
                                .font(.system(.body, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(.white.opacity(0.15))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd)
                                .stroke(.white.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, Spacing.xxl)

                    // Already have account? Sign in
                    Button {
                        showingEmailSignIn = true
                    } label: {
                        Text("Already have an account? Sign In")
                            .font(Typography.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    // Divider
                    HStack {
                        Rectangle()
                            .fill(.white.opacity(0.15))
                            .frame(height: 1)
                        Text("or")
                            .font(Typography.caption)
                            .foregroundStyle(.white.opacity(0.5))
                        Rectangle()
                            .fill(.white.opacity(0.15))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, Spacing.xxxl)
                    .padding(.vertical, Spacing.xs)

                    // Skip for now
                    Button {
                        skipAuth()
                    } label: {
                        Text("Skip for now")
                            .font(Typography.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Spacer()
                    .frame(height: Spacing.xxl)

                // Legal
                VStack(spacing: Spacing.xs) {
                    Text("By continuing, you agree to our")
                        .font(Typography.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                    HStack(spacing: Spacing.xs) {
                        if let termsURL = URL(string: "https://dnrcorp1020-dotcom.github.io/GigWallet-Legal/terms-of-service.html") {
                            Link("Terms of Service", destination: termsURL)
                                .underline()
                        }
                        Text("and")
                        if let privacyURL = URL(string: "https://dnrcorp1020-dotcom.github.io/GigWallet-Legal/privacy-policy.html") {
                            Link("Privacy Policy", destination: privacyURL)
                                .underline()
                        }
                    }
                    .font(Typography.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.bottom, Spacing.xl)
            }

            if isLoading || authManager.isAuthenticating {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }
        }
        .sheet(isPresented: $showingEmailRegistration) {
            NavigationStack {
                EmailRegistrationView { profile in
                    showingEmailRegistration = false
                    onComplete()
                }
            }
        }
        .sheet(isPresented: $showingEmailSignIn) {
            NavigationStack {
                EmailSignInView {
                    showingEmailSignIn = false
                    // EmailSignInView already syncs the profile with .email provider.
                    // Do NOT call syncFirebaseUserToProfile() here — its default
                    // provider is .anonymous, which would overwrite the correct .email value.
                    onComplete()
                }
            }
        }
    }

    // MARK: - Auth Handlers

    private func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Invalid Apple credential"
                return
            }

            isLoading = true
            errorMessage = nil

            Task {
                do {
                    let authResult = try await authManager.signInWithApple(credential: credential)

                    // Apple only sends fullName on the VERY FIRST sign-in.
                    // On subsequent sign-ins, fall back to Firebase user's displayName.
                    var givenName = credential.fullName?.givenName
                    var familyName = credential.fullName?.familyName

                    if givenName == nil, let firebaseDisplayName = authResult.user.displayName {
                        let parts = firebaseDisplayName.components(separatedBy: " ")
                        givenName = parts.first
                        familyName = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : nil
                    }

                    syncFirebaseUserToProfile(
                        firebaseUID: authResult.user.uid,
                        email: authResult.user.email,
                        firstName: givenName,
                        lastName: familyName,
                        provider: .apple,
                        profileImageURL: authResult.user.photoURL?.absoluteString
                    )

                    isLoading = false
                    onComplete()
                } catch {
                    isLoading = false
                    if let authError = error as? FirebaseAuthError, authError == .cancelled {
                        return
                    }
                    errorMessage = authManager.authError ?? error.localizedDescription
                }
            }

        case .failure(let error):
            // User cancelled is not an error we need to show
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func handleGoogleSignIn() {
        Task {
            do {
                let authResult = try await authManager.signInWithGoogle()

                let displayNameParts = authResult.user.displayName?.components(separatedBy: " ") ?? []

                // Google's default photoURL is 96px — request 400px for crisp avatars
                let photoURL = authResult.user.photoURL?.absoluteString
                    .replacingOccurrences(of: "s96-c", with: "s400-c")

                syncFirebaseUserToProfile(
                    firebaseUID: authResult.user.uid,
                    email: authResult.user.email,
                    firstName: displayNameParts.first,
                    lastName: displayNameParts.count > 1 ? displayNameParts.dropFirst().joined(separator: " ") : nil,
                    provider: .google,
                    profileImageURL: photoURL
                )

                onComplete()
            } catch {
                if let authError = error as? FirebaseAuthError, authError == .cancelled {
                    return  // User cancelled — don't show error
                }
                errorMessage = authManager.authError ?? error.localizedDescription
            }
        }
    }

    private func skipAuth() {
        // Create anonymous profile only if none exists — user can sign in later from Settings
        if profiles.first == nil {
            let profile = UserProfile(authProvider: .anonymous)
            modelContext.insert(profile)
        }
        onComplete()
    }

    // MARK: - Profile Sync

    /// Syncs Firebase user data to the local SwiftData UserProfile.
    /// Called after any successful sign-in (Apple, Google, Email).
    private func syncFirebaseUserToProfile(
        firebaseUID: String? = nil,
        email: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        provider: AuthProvider = .anonymous,
        profileImageURL: String? = nil
    ) {
        let uid = firebaseUID ?? authManager.currentFirebaseUser?.uid ?? ""
        let userEmail = email ?? authManager.currentFirebaseUser?.email

        if let existing = profiles.first {
            // Update existing profile — preserve non-nil fields
            if let firstName, !firstName.isEmpty { existing.firstName = firstName }
            if let lastName, !lastName.isEmpty { existing.lastName = lastName }
            if let userEmail, !userEmail.isEmpty { existing.email = userEmail }
            if let profileImageURL, !profileImageURL.isEmpty { existing.profileImageURL = profileImageURL }
            existing.authProvider = provider
            existing.authProviderUserId = uid
            existing.hasCompletedRegistration = true
            existing.updatedAt = .now
        } else {
            let profile = UserProfile(
                firstName: firstName ?? "",
                lastName: lastName ?? "",
                email: userEmail ?? "",
                authProvider: provider
            )
            profile.authProviderUserId = uid
            if let profileImageURL { profile.profileImageURL = profileImageURL }
            profile.hasCompletedRegistration = true
            modelContext.insert(profile)
        }
    }
}

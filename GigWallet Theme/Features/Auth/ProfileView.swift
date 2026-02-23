import SwiftUI
import SwiftData

/// Profile management view — edit name, email, phone, view auth provider, sign out
struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppState.self) private var appState
    @Bindable var profile: UserProfile

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    @State private var phoneNumber: String = ""
    @State private var showingSaveConfirmation = false
    @State private var showingSignOutConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var showingAvatarPicker = false
    @State private var isResendingVerification = false
    @State private var verificationSent = false
    @State private var verificationError: String?

    private let authManager = FirebaseAuthManager.shared

    var body: some View {
        List {
            // Avatar & name
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: Spacing.md) {
                        // Avatar (tap to change)
                        Button {
                            showingAvatarPicker = true
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                ProfileAvatarView(
                                    profileImageURL: profile.profileImageURL,
                                    initials: profile.initials,
                                    size: 88
                                )

                                // Camera badge
                                ZStack {
                                    Circle()
                                        .fill(BrandColors.primary)
                                        .frame(width: 28, height: 28)
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                                .offset(x: 2, y: 2)
                            }
                        }
                        .buttonStyle(.plain)

                        VStack(spacing: Spacing.xxs) {
                            Text(profile.displayName)
                                .font(Typography.title)
                            if profile.isLoggedIn {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: authProviderIcon)
                                        .font(.system(size: 12))
                                    Text("Signed in with \(profile.authProvider.displayName)")
                                        .font(Typography.caption)
                                }
                                .foregroundStyle(BrandColors.textTertiary)
                            }
                        }
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            // Email Verification Status (for email/password users)
            if profile.authProvider == .email && authManager.isAuthenticated {
                Section("Email Verification") {
                    HStack {
                        Label(
                            authManager.isEmailVerified ? "Email Verified" : "Email Not Verified",
                            systemImage: authManager.isEmailVerified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(authManager.isEmailVerified ? BrandColors.success : BrandColors.warning)
                        Spacer()
                    }

                    if !authManager.isEmailVerified {
                        Button {
                            resendVerificationEmail()
                        } label: {
                            HStack {
                                if isResendingVerification {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "envelope.arrow.triangle.branch.fill")
                                }
                                Text(verificationSent ? "Verification Sent!" : "Resend Verification Email")
                            }
                            .foregroundStyle(verificationSent ? BrandColors.success : BrandColors.primary)
                        }
                        .disabled(isResendingVerification || verificationSent)

                        if let error = verificationError {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.red)
                                    .font(.system(size: 14))
                                Text(error)
                                    .font(Typography.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }

            // Editable fields
            Section("Personal Information") {
                HStack {
                    Label("First Name", systemImage: "person.fill")
                        .font(Typography.body)
                    Spacer()
                    TextField("First Name", text: $firstName)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(BrandColors.textSecondary)
                }

                HStack {
                    Label("Last Name", systemImage: "person")
                        .font(Typography.body)
                    Spacer()
                    TextField("Last Name", text: $lastName)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(BrandColors.textSecondary)
                }

                HStack {
                    Label("Email", systemImage: "envelope.fill")
                        .font(Typography.body)
                    Spacer()
                    TextField("email@example.com", text: $email)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .foregroundStyle(BrandColors.textSecondary)
                }

                HStack {
                    Label("Phone", systemImage: "phone.fill")
                        .font(Typography.body)
                    Spacer()
                    TextField("(555) 555-5555", text: $phoneNumber)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.phonePad)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }

            // Account info
            Section("Account") {
                HStack {
                    Label("Auth Provider", systemImage: authProviderIcon)
                    Spacer()
                    Text(profile.authProvider.displayName)
                        .foregroundStyle(BrandColors.textSecondary)
                }

                HStack {
                    Label("Subscription", systemImage: "star.fill")
                    Spacer()
                    GWBadge(
                        profile.isPremium ? "Pro" : "Free",
                        color: profile.isPremium ? BrandColors.primary : BrandColors.textTertiary
                    )
                }

                HStack {
                    Label("Member Since", systemImage: "calendar")
                    Spacer()
                    Text(profile.createdAt, style: .date)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }

            // Sign Out
            if profile.isLoggedIn || authManager.isAuthenticated {
                Section {
                    Button(role: .destructive) {
                        showingSignOutConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                }

                // Delete Account
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Account", systemImage: "trash.fill")
                                .font(Typography.caption)
                            Spacer()
                        }
                        .foregroundStyle(BrandColors.textTertiary)
                    }
                } footer: {
                    Text("This permanently removes your account and all data from our servers. Your local data on this device will be preserved.")
                        .font(Typography.caption2)
                }
            }
        }
        .listStyle(.insetGrouped)
        .gwNavigationTitle("My ", accent: "Profile", icon: "person.circle.fill")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveProfile()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            firstName = profile.firstName
            lastName = profile.lastName
            email = profile.email
            phoneNumber = profile.phoneNumber

            // Reload Firebase user to refresh email verification status.
            // Firebase caches user data locally — after verifying via email link,
            // the app still shows the stale "not verified" state until we reload.
            if profile.authProvider == .email && authManager.isAuthenticated {
                Task {
                    try? await authManager.reloadCurrentUser()
                }
            }
        }
        .alert("Sign Out?", isPresented: $showingSignOutConfirmation) {
            Button("Sign Out", role: .destructive) {
                performSignOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your financial data will stay on this device. You can sign back in anytime.")
        }
        .alert("Delete Account?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                performDeleteAccount()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your account from our servers. This cannot be undone.")
        }
        .onChange(of: scenePhase) { _, newPhase in
            // When user returns from Safari after clicking verification link,
            // reload Firebase user to pick up the new verification status.
            if newPhase == .active && profile.authProvider == .email && authManager.isAuthenticated {
                Task {
                    try? await authManager.reloadCurrentUser()
                }
            }
        }
        .sheet(isPresented: $showingAvatarPicker) {
            NavigationStack {
                ProfileAvatarPickerView(profileImageURL: Bindable(profile).profileImageURL)
            }
        }
    }

    private var authProviderIcon: String {
        switch profile.authProvider {
        case .apple: return "apple.logo"
        case .google: return "g.circle.fill"
        case .email: return "envelope.fill"
        case .anonymous: return "person.crop.circle.badge.questionmark"
        }
    }

    private func saveProfile() {
        profile.firstName = firstName.trimmingCharacters(in: .whitespaces)
        profile.lastName = lastName.trimmingCharacters(in: .whitespaces)
        profile.email = email.trimmingCharacters(in: .whitespaces)
        profile.phoneNumber = phoneNumber.trimmingCharacters(in: .whitespaces)
        profile.updatedAt = .now
        dismiss()
    }

    private func performSignOut() {
        // Reset local profile to anonymous
        profile.authProvider = .anonymous
        profile.authProviderUserId = ""
        profile.hasCompletedRegistration = false
        profile.updatedAt = .now

        // Dismiss this sheet first, then sign out after a brief delay.
        // AppState.signOut() sets hasCompletedAuth = false, causing ContentView
        // to swap to AuthView and dismiss any remaining sheets.
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            appState.signOut()
        }
    }

    private func performDeleteAccount() {
        Task {
            do {
                try await authManager.deleteAccount()
            } catch {
                // Even if Firebase delete fails, proceed with local cleanup
                #if DEBUG
                print("Firebase account deletion error: \(error)")
                #endif
            }

            // Reset local profile
            profile.authProvider = .anonymous
            profile.authProviderUserId = ""
            profile.hasCompletedRegistration = false
            profile.updatedAt = .now

            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                appState.signOut()
            }
        }
    }

    private func resendVerificationEmail() {
        isResendingVerification = true
        verificationError = nil
        Task {
            do {
                try await authManager.sendEmailVerification()
                withAnimation {
                    verificationSent = true
                    isResendingVerification = false
                }
            } catch {
                withAnimation {
                    isResendingVerification = false
                    verificationError = "Could not send verification email. Please try again later."
                }
                HapticManager.shared.error()
            }
        }
    }
}

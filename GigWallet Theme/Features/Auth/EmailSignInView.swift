import SwiftUI
import SwiftData

/// Email sign-in view for returning users — email + password with "Forgot Password?" support.
struct EmailSignInView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?
    @State private var showingPasswordReset = false
    @State private var resetEmailSent = false

    @FocusState private var focusedField: SignInField?

    private let authManager = FirebaseAuthManager.shared

    let onComplete: () -> Void

    enum SignInField {
        case email, password
    }

    private var isFormValid: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        return !trimmedEmail.isEmpty &&
            trimmedEmail.contains("@") && trimmedEmail.contains(".") &&
            !password.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                // Header
                VStack(spacing: Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(BrandColors.primary.opacity(0.1))
                            .frame(width: 80, height: 80)

                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(BrandColors.primary)
                    }

                    Text("Welcome Back")
                        .font(Typography.title)

                    Text("Sign in with your email and password")
                        .font(Typography.subheadline)
                        .foregroundStyle(BrandColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Spacing.xl)

                // Form fields
                VStack(spacing: Spacing.lg) {
                    // Email
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Email Address")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)

                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(BrandColors.textTertiary)
                                .frame(width: 20)

                            TextField("Email Address", text: $email)
                                .font(Typography.body)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .email)
                        }
                        .padding(Spacing.md)
                        .background(BrandColors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd)
                                .stroke(
                                    focusedField == .email ? BrandColors.primary : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                    }

                    // Password
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Password")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)

                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(BrandColors.textTertiary)
                                .frame(width: 20)

                            SecureField("Password", text: $password)
                                .font(Typography.body)
                                .textInputAutocapitalization(.never)
                                .focused($focusedField, equals: .password)
                        }
                        .padding(Spacing.md)
                        .background(BrandColors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd)
                                .stroke(
                                    focusedField == .password ? BrandColors.primary : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                    }

                    // Forgot password
                    HStack {
                        Spacer()
                        Button {
                            showingPasswordReset = true
                        } label: {
                            Text("Forgot Password?")
                                .font(Typography.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(BrandColors.primary)
                        }
                    }
                }
                .padding(.horizontal, Spacing.lg)

                if let errorMessage {
                    Text(errorMessage)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.destructive)
                        .padding(.horizontal, Spacing.lg)
                        .multilineTextAlignment(.center)
                }

                if resetEmailSent {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(BrandColors.success)
                        Text("Password reset email sent!")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.success)
                    }
                    .padding(.horizontal, Spacing.lg)
                }

                // Sign in button
                GWButton("Sign In", icon: "arrow.right.circle.fill") {
                    signIn()
                }
                .padding(.horizontal, Spacing.lg)
                .disabled(!isFormValid || isSubmitting)
                .opacity(isFormValid ? 1.0 : 0.5)

                Spacer()
            }
        }
        .background(BrandColors.groupedBackground)
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
        .alert("Reset Password", isPresented: $showingPasswordReset) {
            TextField("Email Address", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            Button("Send Reset Link") {
                sendPasswordReset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter your email address and we'll send you a link to reset your password.")
        }
    }

    private func signIn() {
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                let result = try await authManager.signInWithEmail(
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password
                )

                // Sync to local profile
                let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
                if let existing = profiles.first {
                    if existing.email.isEmpty { existing.email = trimmedEmail }
                    existing.authProvider = .email
                    existing.authProviderUserId = result.user.uid
                    existing.hasCompletedRegistration = true
                    existing.updatedAt = .now

                    // Update name from Firebase if local is empty
                    if existing.firstName.isEmpty, let displayName = result.user.displayName {
                        let parts = displayName.components(separatedBy: " ")
                        existing.firstName = parts.first ?? ""
                        if parts.count > 1 {
                            existing.lastName = parts.dropFirst().joined(separator: " ")
                        }
                    }
                } else {
                    let displayNameParts = result.user.displayName?.components(separatedBy: " ") ?? []
                    let profile = UserProfile(
                        firstName: displayNameParts.first ?? "",
                        lastName: displayNameParts.count > 1 ? displayNameParts.dropFirst().joined(separator: " ") : "",
                        email: trimmedEmail,
                        authProvider: .email
                    )
                    profile.authProviderUserId = result.user.uid
                    profile.hasCompletedRegistration = true
                    modelContext.insert(profile)
                }

                isSubmitting = false
                onComplete()
            } catch {
                isSubmitting = false
                errorMessage = authManager.authError ?? error.localizedDescription
            }
        }
    }

    private func sendPasswordReset() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        guard !trimmedEmail.isEmpty else {
            errorMessage = "Please enter your email address first."
            return
        }

        Task {
            do {
                try await authManager.sendPasswordReset(email: trimmedEmail)
                withAnimation {
                    resetEmailSent = true
                    errorMessage = nil
                }
                // Hide the success message after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation { resetEmailSent = false }
                }
            } catch {
                errorMessage = authManager.authError ?? error.localizedDescription
            }
        }
    }
}

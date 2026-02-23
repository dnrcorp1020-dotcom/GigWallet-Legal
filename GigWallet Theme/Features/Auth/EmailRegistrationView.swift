import SwiftUI
import SwiftData

/// Email registration form — creates a new Firebase account with email + password.
/// After successful signup, sends email verification and syncs profile to SwiftData.
struct EmailRegistrationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var phoneNumber: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?
    @State private var showingVerificationConfirmation = false

    @FocusState private var focusedField: Field?

    private let authManager = FirebaseAuthManager.shared

    let onComplete: (UserProfile) -> Void

    enum Field {
        case firstName, lastName, email, password, confirmPassword, phone
    }

    private var isFormValid: Bool {
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        return !trimmedFirst.isEmpty &&
            !trimmedEmail.isEmpty &&
            trimmedEmail.contains("@") && trimmedEmail.contains(".") &&
            password.count >= 8 &&
            password == confirmPassword
    }

    private var passwordError: String? {
        if password.isEmpty { return nil }
        if password.count < 8 { return "Password must be at least 8 characters" }
        if !confirmPassword.isEmpty && password != confirmPassword { return "Passwords don't match" }
        return nil
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

                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 36))
                            .foregroundStyle(BrandColors.primary)
                    }

                    Text("Create Your Account")
                        .font(Typography.title)

                    Text("Track your gig income and maximize deductions")
                        .font(Typography.subheadline)
                        .foregroundStyle(BrandColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Spacing.lg)

                // Form fields
                VStack(spacing: Spacing.lg) {
                    // Name row
                    HStack(spacing: Spacing.md) {
                        AuthTextField(
                            title: "First Name",
                            text: $firstName,
                            icon: "person.fill",
                            focused: $focusedField,
                            field: .firstName
                        )

                        AuthTextField(
                            title: "Last Name",
                            text: $lastName,
                            icon: nil,
                            focused: $focusedField,
                            field: .lastName
                        )
                    }

                    AuthTextField(
                        title: "Email Address",
                        text: $email,
                        icon: "envelope.fill",
                        keyboardType: .emailAddress,
                        autocapitalization: .never,
                        focused: $focusedField,
                        field: .email
                    )

                    // Password
                    AuthSecureField(
                        title: "Password",
                        text: $password,
                        icon: "lock.fill",
                        focused: $focusedField,
                        field: .password
                    )

                    // Confirm Password
                    AuthSecureField(
                        title: "Confirm Password",
                        text: $confirmPassword,
                        icon: "lock.shield.fill",
                        focused: $focusedField,
                        field: .confirmPassword
                    )

                    // Password validation feedback
                    if let passwordError {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                            Text(passwordError)
                                .font(Typography.caption)
                        }
                        .foregroundStyle(BrandColors.destructive)
                    } else if password.count >= 8 && password == confirmPassword {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                            Text("Passwords match")
                                .font(Typography.caption)
                        }
                        .foregroundStyle(BrandColors.success)
                    }

                    AuthTextField(
                        title: "Phone (optional)",
                        text: $phoneNumber,
                        icon: "phone.fill",
                        keyboardType: .phonePad,
                        focused: $focusedField,
                        field: .phone
                    )
                }
                .padding(.horizontal, Spacing.lg)

                if let errorMessage {
                    Text(errorMessage)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.destructive)
                        .padding(.horizontal, Spacing.lg)
                        .multilineTextAlignment(.center)
                }

                // Submit
                GWButton("Create Account", icon: "checkmark.circle.fill") {
                    createAccount()
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
        .alert("Check Your Email", isPresented: $showingVerificationConfirmation) {
            Button("OK") {
                // Profile already created — complete the flow
                if let profile = profiles.first {
                    onComplete(profile)
                }
            }
        } message: {
            Text("We sent a verification link to \(email). Please verify your email to secure your account.")
        }
    }

    private func createAccount() {
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
                let trimmedFirstName = firstName.trimmingCharacters(in: .whitespaces)
                let trimmedLastName = lastName.trimmingCharacters(in: .whitespaces)

                let result = try await authManager.signUpWithEmail(
                    email: trimmedEmail,
                    password: password,
                    firstName: trimmedFirstName,
                    lastName: trimmedLastName
                )

                // Sync to local SwiftData profile
                let profile: UserProfile
                if let existing = profiles.first {
                    existing.firstName = trimmedFirstName
                    existing.lastName = trimmedLastName
                    existing.email = trimmedEmail
                    existing.phoneNumber = phoneNumber.trimmingCharacters(in: .whitespaces)
                    existing.authProvider = .email
                    existing.authProviderUserId = result.user.uid
                    existing.hasCompletedRegistration = true
                    existing.updatedAt = .now
                    profile = existing
                } else {
                    profile = UserProfile(
                        firstName: trimmedFirstName,
                        lastName: trimmedLastName,
                        email: trimmedEmail,
                        phoneNumber: phoneNumber.trimmingCharacters(in: .whitespaces),
                        authProvider: .email
                    )
                    profile.authProviderUserId = result.user.uid
                    profile.hasCompletedRegistration = true
                    modelContext.insert(profile)
                }

                isSubmitting = false
                showingVerificationConfirmation = true

            } catch {
                isSubmitting = false
                errorMessage = authManager.authError ?? error.localizedDescription
            }
        }
    }
}

// MARK: - Secure Text Field

struct AuthSecureField: View {
    let title: String
    @Binding var text: String
    let icon: String?
    var focused: FocusState<EmailRegistrationView.Field?>.Binding
    let field: EmailRegistrationView.Field

    @State private var isSecured = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)

            HStack(spacing: Spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(BrandColors.textTertiary)
                        .frame(width: 20)
                }

                Group {
                    if isSecured {
                        SecureField(title, text: $text)
                    } else {
                        TextField(title, text: $text)
                    }
                }
                .font(Typography.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(focused, equals: field)

                Button {
                    isSecured.toggle()
                } label: {
                    Image(systemName: isSecured ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(BrandColors.textTertiary)
                }
            }
            .padding(Spacing.md)
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd)
                    .stroke(
                        focused.wrappedValue == field ? BrandColors.primary : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
    }
}

// MARK: - Styled Text Field (updated for new Field enum)

struct AuthTextField: View {
    let title: String
    @Binding var text: String
    let icon: String?
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .words
    var focused: FocusState<EmailRegistrationView.Field?>.Binding
    let field: EmailRegistrationView.Field

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)

            HStack(spacing: Spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(BrandColors.textTertiary)
                        .frame(width: 20)
                }

                TextField(title, text: $text)
                    .font(Typography.body)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
                    .focused(focused, equals: field)
            }
            .padding(Spacing.md)
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd)
                    .stroke(
                        focused.wrappedValue == field ? BrandColors.primary : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
    }
}

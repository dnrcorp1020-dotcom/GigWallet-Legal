import SwiftUI
import SwiftData
import StoreKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query private var profiles: [UserProfile]
    @Query private var connections: [PlatformConnection]

    @State private var showingBankConnection = false
    @State private var showingProfile = false
    @State private var showingAuthView = false
    @State private var showingSignOutConfirmation = false
    @State private var showingFinancialPlanner = false
    @State private var showingArgyleConnection = false
    #if DEBUG
    @State private var showingDemoDataConfirmation = false
    @State private var demoDataLoaded = false
    @State private var clearDataError: String?
    #endif

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        List {
            // Profile
            Section {
                Button {
                    // If user is actually signed in, show profile editor.
                    // If anonymous (skipped auth or signed out), show AuthView to sign in.
                    if let profile, profile.isLoggedIn {
                        showingProfile = true
                    } else {
                        showingAuthView = true
                    }
                } label: {
                    HStack(spacing: Spacing.md) {
                        if let profile, profile.isLoggedIn {
                            ProfileAvatarView(
                                profileImageURL: profile.profileImageURL,
                                initials: profile.initials,
                                size: 52
                            )
                        } else {
                            ZStack {
                                Circle()
                                    .fill(BrandColors.primary.opacity(0.12))
                                    .frame(width: 52, height: 52)
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(BrandColors.primary)
                            }
                        }

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text({
                                let name = profile?.displayName ?? ""
                                return name.isEmpty ? L10n.settingsYourProfile : name
                            }())
                                .font(Typography.headline)
                                .foregroundStyle(BrandColors.textPrimary)

                            if let profile, profile.isLoggedIn {
                                Text(profile.email.isEmpty ? profile.authProvider.displayName : profile.email)
                                    .font(Typography.caption)
                                    .foregroundStyle(BrandColors.textSecondary)
                            } else {
                                Text(L10n.settingsSignInToSync)
                                    .font(Typography.caption)
                                    .foregroundStyle(BrandColors.primary)
                            }
                        }

                        Spacer()

                        GWBadge(
                            profile?.isPremium == true ? "Pro" : "Free",
                            color: profile?.isPremium == true ? BrandColors.primary : BrandColors.textTertiary
                        )

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }
            }

            // Auto-Sync — PREMIUM
            Section(L10n.settingsAutoSync) {
                Button {
                    if profile?.isPremium == true {
                        showingBankConnection = true
                    } else {
                        appState.showingPaywall = true
                    }
                } label: {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "building.columns.fill")
                            .foregroundStyle(BrandColors.primary)
                            .frame(width: 24)
                        Text(L10n.settingsConnectBank)
                            .font(Typography.bodyMedium)
                            .foregroundStyle(BrandColors.textPrimary)
                        Spacer()
                        if profile?.isPremium != true {
                            GWProBadge()
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }

                Button {
                    if profile?.isPremium == true {
                        showingArgyleConnection = true
                    } else {
                        appState.showingPaywall = true
                    }
                } label: {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .foregroundStyle(BrandColors.primary)
                            .frame(width: 24)
                        Text(L10n.settingsConnectPlatforms)
                            .font(Typography.bodyMedium)
                            .foregroundStyle(BrandColors.textPrimary)
                        Spacer()
                        if profile?.isPremium != true {
                            GWProBadge()
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }
            }

            // Tax Profile (editable)
            if let profile {
                Section("Tax Profile \u{00B7} \(String(DateHelper.currentTaxYear))") {
                    Picker(selection: Bindable(profile).filingStatus) {
                        ForEach(FilingStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    } label: {
                        Label("Filing Status", systemImage: "doc.text")
                    }

                    Picker(selection: Bindable(profile).stateCode) {
                        ForEach(Self.usStates, id: \.code) { state in
                            Text("\(state.code) - \(state.name)").tag(state.code)
                        }
                    } label: {
                        Label("State", systemImage: "map")
                    }

                    Picker(selection: Binding(
                        get: { profile.gigWorkerType },
                        set: { profile.gigWorkerType = $0 }
                    )) {
                        ForEach(GigWorkerType.allCases) { type in
                            Text(type.shortName).tag(type)
                        }
                    } label: {
                        Label("Work Type", systemImage: "briefcase.fill")
                    }

                    if profile.gigWorkerType == .sideGig {
                        HStack {
                            Label("W-2 Withholding/yr", systemImage: "building.2.fill")
                            Spacer()
                            TextField("$0", value: Bindable(profile).estimatedW2Withholding, format: .currency(code: "USD"))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 120)
                        }
                    }

                    Picker(selection: Binding(
                        get: { profile.deductionMethod },
                        set: { profile.deductionMethod = $0 }
                    )) {
                        ForEach(DeductionMethod.allCases) { method in
                            Text(method.shortName).tag(method)
                        }
                    } label: {
                        Label("Deduction Method", systemImage: "doc.text.fill")
                    }

                    if profile.deductionMethod == .itemized {
                        HStack {
                            Label("Itemized Amount", systemImage: "list.clipboard.fill")
                            Spacer()
                            TextField("$0", value: Bindable(profile).estimatedItemizedDeductions, format: .currency(code: "USD"))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 120)
                        }
                    }

                    // Tax credits summary
                    if !profile.selectedTaxCredits.isEmpty {
                        HStack {
                            Label("Tax Credits", systemImage: "star.fill")
                            Spacer()
                            Text("\(String(profile.selectedTaxCredits.count)) selected")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.success)
                        }
                    }

                    NavigationLink {
                        W2WithholdingGuideView(profile: profile)
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(BrandColors.primary)
                            Text("Tax Profile Guide")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.primary)
                        }
                    }
                }

                // Safe Harbor & Deductions
                Section("Tax Optimizer") {
                    HStack {
                        Label("Prior Year Tax", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        TextField("$0", value: Bindable(profile).priorYearTax, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }

                    HStack {
                        Label("Home Office (sq ft)", systemImage: "house.fill")
                        Spacer()
                        TextField("0", value: Bindable(profile).homeOfficeSquareFeet, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                    }

                    // Show calculated home office deduction
                    if profile.homeOfficeSquareFeet > 0 {
                        let simplified = min(profile.homeOfficeSquareFeet, 300) * 5
                        HStack {
                            Text("Simplified Deduction")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textSecondary)
                            Spacer()
                            Text(CurrencyFormatter.format(simplified))
                                .font(Typography.moneyCaption)
                                .foregroundStyle(BrandColors.success)
                        }
                    }

                    if profile.priorYearTax > 0 {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "shield.checkered")
                                .font(.system(size: 12))
                                .foregroundStyle(BrandColors.success)
                            Text("Safe harbor optimizer active — lower quarterly payments")
                                .font(Typography.caption2)
                                .foregroundStyle(BrandColors.success)
                        }
                    } else {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(BrandColors.textTertiary)
                            Text("Enter last year's total tax to unlock safe harbor savings")
                                .font(Typography.caption2)
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                    }
                }
            } else {
                Section("Tax Profile") {
                    HStack {
                        Label("Filing Status", systemImage: "doc.text")
                        Spacer()
                        Text("Single")
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                    HStack {
                        Label("Tax Year", systemImage: "calendar")
                        Spacer()
                        Text(String(DateHelper.currentTaxYear))
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                }
            }

            // Notifications
            if let profile {
                Section {
                    Toggle(isOn: Bindable(profile).notificationsEnabled) {
                        Label(L10n.settingsPushNotifications, systemImage: "bell.badge.fill")
                    }
                    .tint(BrandColors.primary)
                    .onChange(of: profile.notificationsEnabled) { _, enabled in
                        if enabled {
                            Task {
                                let granted = await NotificationService.requestPermission()
                                if !granted {
                                    profile.notificationsEnabled = false
                                }
                            }
                        } else {
                            NotificationService.removeAllNotifications()
                        }
                    }
                } header: {
                    Text(L10n.settingsNotifications)
                } footer: {
                    if profile.notificationsEnabled {
                        Text("Tax deadlines, weekly summaries, goal reminders, and event alerts are all enabled.")
                    }
                }
            }

            // Appearance
            Section("Appearance") {
                Picker(selection: Binding(
                    get: { appState.appearanceMode },
                    set: { appState.appearanceMode = $0 }
                )) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon)
                            .tag(mode)
                    }
                } label: {
                    Label("Theme", systemImage: "paintbrush.fill")
                }
            }

            // Dashboard
            Section("Dashboard") {
                Toggle(isOn: Binding(
                    get: { DashboardCardOrderManager.shared.showAllCards },
                    set: { DashboardCardOrderManager.shared.showAllCards = $0 }
                )) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show All Cards")
                            Text("Override progressive unlock — show every card")
                                .font(Typography.caption2)
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                    } icon: {
                        Image(systemName: "square.grid.2x2")
                    }
                }
                .tint(BrandColors.primary)
            }

            // Connected Platforms — only show when there are connections
            if !connections.isEmpty {
                Section(L10n.settingsConnectedPlatforms) {
                    ForEach(connections) { connection in
                        HStack(spacing: Spacing.md) {
                            Image(systemName: connection.platform.sfSymbol)
                                .foregroundStyle(connection.platform.brandColor)
                                .frame(width: 24)

                            Text(connection.platform.displayName)

                            Spacer()

                            HStack(spacing: Spacing.xs) {
                                Image(systemName: connection.connectionStatus.sfSymbol)
                                    .foregroundStyle(connection.connectionStatus.color)
                                    .font(.system(size: 14))

                                Text(connection.connectionStatus.rawValue)
                                    .font(Typography.caption)
                                    .foregroundStyle(connection.connectionStatus.color)
                            }
                        }
                    }
                }
            }

            // Tools
            Section("Tools") {
                // Financial Planner (PREMIUM)
                Button {
                    if profile?.isPremium == true {
                        showingFinancialPlanner = true
                    } else {
                        appState.showingPaywall = true
                    }
                } label: {
                    HStack {
                        Label("Financial Planner", systemImage: "chart.pie.fill")

                        Spacer()

                        if profile?.isPremium != true {
                            GWProBadge()
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }

                NavigationLink {
                    InvoiceListView()
                } label: {
                    Label("Invoices", systemImage: "doc.text.fill")
                }
            }

            // Subscription
            Section(L10n.settingsSubscription) {
                if profile?.isPremium == true {
                    // Already subscribed — show manage option
                    Button {
                        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                            Task {
                                try? await AppStore.showManageSubscriptions(in: scene)
                            }
                        }
                    } label: {
                        HStack {
                            Label("Manage Subscription", systemImage: "creditcard.fill")
                                .foregroundStyle(BrandColors.textPrimary)
                            Spacer()
                            GWBadge("Active", color: BrandColors.success)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                    }
                } else {
                    Button {
                        appState.showingPaywall = true
                    } label: {
                        HStack {
                            Label(L10n.settingsUpgradePremium, systemImage: "star.fill")
                                .foregroundStyle(BrandColors.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                    }
                }
            }

            // Sign Out (only if user is authenticated)
            if let profile, (profile.isLoggedIn || FirebaseAuthManager.shared.isAuthenticated) {
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
                } footer: {
                    if let email = profile.email as String?, !email.isEmpty {
                        Text("Signed in as \(email)")
                    }
                }
            }

            // Developer Tools (DEBUG only — stripped from release builds)
            #if DEBUG
            Section {
                Button {
                    showingDemoDataConfirmation = true
                } label: {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "flask.fill")
                            .foregroundStyle(.purple)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Load Demo Data")
                                .font(Typography.bodyMedium)
                                .foregroundStyle(BrandColors.textPrimary)
                            Text("Seeds 4 months of realistic gig data")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                        Spacer()
                        if demoDataLoaded {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(BrandColors.success)
                        }
                    }
                }

                Button {
                    // Clear all data except profile — use do/catch so partial failures are visible
                    clearDataError = nil
                    do {
                        try modelContext.delete(model: IncomeEntry.self)
                        try modelContext.delete(model: ExpenseEntry.self)
                        try modelContext.delete(model: MileageTrip.self)
                        try modelContext.delete(model: TaxPayment.self)
                        try modelContext.delete(model: TaxVaultEntry.self)
                        try modelContext.delete(model: PlatformConnection.self)
                        try modelContext.delete(model: BudgetItem.self)
                        try modelContext.save()
                        demoDataLoaded = false
                        HapticManager.shared.success()
                    } catch {
                        clearDataError = "Some data could not be deleted: \(error.localizedDescription)"
                        HapticManager.shared.error()
                    }
                } label: {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "trash.fill")
                            .foregroundStyle(.red)
                            .frame(width: 24)
                        Text("Clear All Data")
                            .font(Typography.bodyMedium)
                            .foregroundStyle(.red)
                        Spacer()
                    }
                }

                if let error = clearDataError {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.system(size: 14))
                        Text(error)
                            .font(Typography.caption)
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 10))
                    Text("Developer Tools")
                }
            } footer: {
                Text("This section only appears in DEBUG builds and is automatically removed from App Store releases.")
            }
            #endif

            // About
            Section("About") {
                HStack {
                    Label(L10n.settingsVersion, systemImage: "info.circle")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                        .foregroundStyle(BrandColors.textSecondary)
                }

                if let url = URL(string: "https://dnrcorp1020-dotcom.github.io/GigWallet-Legal/privacy-policy.html") {
                    Link(destination: url) {
                        Label(L10n.settingsPrivacy, systemImage: "lock.shield")
                    }
                }

                if let url = URL(string: "https://dnrcorp1020-dotcom.github.io/GigWallet-Legal/terms-of-service.html") {
                    Link(destination: url) {
                        Label(L10n.settingsTerms, systemImage: "doc.plaintext")
                    }
                }

                if let url = URL(string: "mailto:support@gigwallet.app") {
                    Link(destination: url) {
                        Label(L10n.settingsSupport, systemImage: "questionmark.circle")
                    }
                }
            }
        }
        .tint(BrandColors.primary)
        .accentColor(BrandColors.primary)
        .listStyle(.insetGrouped)
        .gwNavigationTitle("", accent: L10n.settings, icon: "gearshape.fill")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showingFinancialPlanner) {
            NavigationStack {
                FinancialPlannerView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { showingFinancialPlanner = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingArgyleConnection) {
            ArgyleConnectionView()
        }
        .sheet(isPresented: $showingBankConnection) {
            BankConnectionView()
        }
        .sheet(isPresented: $showingProfile) {
            if let profile {
                NavigationStack {
                    ProfileView(profile: profile)
                }
            }
        }
        .sheet(isPresented: $showingAuthView) {
            AuthView {
                showingAuthView = false
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
        #if DEBUG
        .alert("Load Demo Data?", isPresented: $showingDemoDataConfirmation) {
            Button("Load Demo Data", role: .destructive) {
                DataSeeder.seedDemoData(context: modelContext)
                appState.markAuthCompleted()
                appState.markOnboardingCompleted()
                demoDataLoaded = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace all existing data with 4 months of realistic demo data. Profile will be set to Pro.")
        }
        #endif
    }

    private func performSignOut() {
        // Reset local profile to anonymous and clear personal data
        if let profile {
            profile.authProvider = .anonymous
            profile.authProviderUserId = ""
            profile.firstName = ""
            profile.lastName = ""
            profile.email = ""
            profile.phoneNumber = ""
            profile.profileImageURL = ""
            profile.hasCompletedRegistration = false
            profile.updatedAt = .now
        }

        // Dismiss Settings sheet, then sign out after a brief delay.
        // AppState.signOut() sets hasCompletedAuth = false, causing ContentView
        // to swap to AuthView.
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            appState.signOut()
        }
    }
}

// MARK: - US States Data

extension SettingsView {
    struct USState {
        let code: String
        let name: String
    }

    static let usStates: [USState] = [
        USState(code: "AL", name: "Alabama"), USState(code: "AK", name: "Alaska"),
        USState(code: "AZ", name: "Arizona"), USState(code: "AR", name: "Arkansas"),
        USState(code: "CA", name: "California"), USState(code: "CO", name: "Colorado"),
        USState(code: "CT", name: "Connecticut"), USState(code: "DE", name: "Delaware"),
        USState(code: "DC", name: "District of Columbia"), USState(code: "FL", name: "Florida"),
        USState(code: "GA", name: "Georgia"), USState(code: "HI", name: "Hawaii"),
        USState(code: "ID", name: "Idaho"), USState(code: "IL", name: "Illinois"),
        USState(code: "IN", name: "Indiana"), USState(code: "IA", name: "Iowa"),
        USState(code: "KS", name: "Kansas"), USState(code: "KY", name: "Kentucky"),
        USState(code: "LA", name: "Louisiana"), USState(code: "ME", name: "Maine"),
        USState(code: "MD", name: "Maryland"), USState(code: "MA", name: "Massachusetts"),
        USState(code: "MI", name: "Michigan"), USState(code: "MN", name: "Minnesota"),
        USState(code: "MS", name: "Mississippi"), USState(code: "MO", name: "Missouri"),
        USState(code: "MT", name: "Montana"), USState(code: "NE", name: "Nebraska"),
        USState(code: "NV", name: "Nevada"), USState(code: "NH", name: "New Hampshire"),
        USState(code: "NJ", name: "New Jersey"), USState(code: "NM", name: "New Mexico"),
        USState(code: "NY", name: "New York"), USState(code: "NC", name: "North Carolina"),
        USState(code: "ND", name: "North Dakota"), USState(code: "OH", name: "Ohio"),
        USState(code: "OK", name: "Oklahoma"), USState(code: "OR", name: "Oregon"),
        USState(code: "PA", name: "Pennsylvania"), USState(code: "RI", name: "Rhode Island"),
        USState(code: "SC", name: "South Carolina"), USState(code: "SD", name: "South Dakota"),
        USState(code: "TN", name: "Tennessee"), USState(code: "TX", name: "Texas"),
        USState(code: "UT", name: "Utah"), USState(code: "VT", name: "Vermont"),
        USState(code: "VA", name: "Virginia"), USState(code: "WA", name: "Washington"),
        USState(code: "WV", name: "West Virginia"), USState(code: "WI", name: "Wisconsin"),
        USState(code: "WY", name: "Wyoming"),
    ]
}


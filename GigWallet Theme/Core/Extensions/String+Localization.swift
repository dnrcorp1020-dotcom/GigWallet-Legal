import Foundation

/// Extension to easily access localized strings
/// Usage: "common.done".localized → "Done" (or "Listo" in Spanish)
extension String {
    var localized: String {
        NSLocalizedString(self, comment: "")
    }

    func localized(with arguments: CVarArg...) -> String {
        String(format: NSLocalizedString(self, comment: ""), arguments: arguments)
    }
}

/// Centralized string keys for type safety
/// These map to the keys in Localizable.strings
enum L10n {
    // MARK: - Common
    static var done: String { "common.done".localized }
    static var cancel: String { "common.cancel".localized }
    static var save: String { "common.save".localized }
    static var delete: String { "common.delete".localized }
    static var edit: String { "common.edit".localized }
    static var add: String { "common.add".localized }
    static var close: String { "common.close".localized }
    static var settings: String { "common.settings".localized }
    static var seeAll: String { "common.seeAll".localized }

    // MARK: - Tabs
    static var tabHome: String { "tab.home".localized }
    static var tabEarnings: String { "tab.earnings".localized }
    static var tabAdd: String { "tab.add".localized }
    static var tabWriteOffs: String { "tab.writeOffs".localized }
    static var tabTaxHQ: String { "tab.taxHQ".localized }

    // MARK: - Dashboard
    static var thisMonth: String { "dashboard.thisMonth".localized }
    static var expenses: String { "dashboard.expenses".localized }
    static var netProfit: String { "dashboard.netProfit".localized }
    static var weeklyGoal: String { "dashboard.weeklyGoal".localized }
    static var goalReached: String { "dashboard.goalReached".localized }
    static var setGoal: String { "dashboard.setGoal".localized }
    static var savingsTips: String { "dashboard.savingsTips".localized }

    // MARK: - Quick Actions
    static var addIncome: String { "quickAction.addIncome".localized }
    static var addExpense: String { "quickAction.addExpense".localized }
    static var addMileage: String { "quickAction.addMileage".localized }

    // MARK: - Tax
    static var taxTitle: String { "tax.title".localized }
    static var grossIncome: String { "tax.grossIncome".localized }
    static var deductions: String { "tax.deductions".localized }
    static var exportSummary: String { "tax.exportSummary".localized }
    static var payIRS: String { "tax.payIRS".localized }

    // MARK: - Goals
    static var setGoalTitle: String { "goal.setTitle".localized }
    static var setGoalButton: String { "goal.setGoal".localized }
    static var removeGoal: String { "goal.removeGoal".localized }
    static var weekly: String { "goal.weekly".localized }
    static var monthly: String { "goal.monthly".localized }

    // MARK: - Auth
    static var signInApple: String { "auth.signInApple".localized }
    static var signInGoogle: String { "auth.signInGoogle".localized }
    static var signInEmail: String { "auth.signInEmail".localized }
    static var skip: String { "auth.skip".localized }

    // MARK: - Earnings Summary
    static var profitMargin: String { "summary.profitMargin".localized }
    static var todayYouKeep: String { "summary.todayYouKeep".localized }
    static var startTracking: String { "dashboard.startTracking".localized }
    static var startTrackingSubtitle: String { "dashboard.startTrackingSubtitle".localized }

    // MARK: - Dashboard Extra
    static var setGoalSubtitle: String { "dashboard.setGoalSubtitle".localized }
    static var toGo: String { "dashboard.toGo".localized }
    static var of: String { "dashboard.of".localized }

    // MARK: - Greeting
    static var greetingStrongMorning: String { "greeting.strongMorning".localized }
    static var greetingGreatAfternoon: String { "greeting.greatAfternoon".localized }
    static var greetingSolidDay: String { "greeting.solidDay".localized }
    static var greetingReadyToGetBack: String { "greeting.readyToGetBack".localized }
    static var greetingEarnedToday: String { "greeting.earnedToday".localized }
    static var greetingEarnedThisWeek: String { "greeting.earnedThisWeek".localized }

    // MARK: - Tax Bite
    static var taxBiteTitle: String { "taxBite.title".localized }
    static var taxBiteYouKeep: String { "taxBite.youKeep".localized }
    static var taxBiteTax: String { "taxBite.tax".localized }
    static var taxBiteEstInPocket: String { "taxBite.estInPocket".localized }
    static var taxBiteNoEarnings: String { "taxBite.noEarnings".localized }
    static var taxBiteDisclaimer: String { "taxBite.disclaimer".localized }

    // MARK: - Quick Actions (Extended)
    static var quickActionIncome: String { "quickAction.income".localized }
    static var quickActionExpense: String { "quickAction.expense".localized }
    static var quickActionMileage: String { "quickAction.mileage".localized }
    static var quickActionCashTip: String { "quickAction.cashTip".localized }
    static var quickActionScan: String { "quickAction.scan".localized }

    // MARK: - Income Momentum
    static var momentumTitle: String { "momentum.title".localized }
    static var momentumThirtyDayAvg: String { "momentum.thirtyDayAvg".localized }
    static var momentumPerDay: String { "momentum.perDay".localized }
    static var momentumToday: String { "momentum.today".localized }
    static var momentumThisWeek: String { "momentum.thisWeek".localized }
    static var momentumLogFirst: String { "momentum.logFirst".localized }

    // MARK: - Tax Countdown
    static var taxCountdownLogMore: String { "taxCountdown.logMore".localized }
    static var taxCountdownPaidInFull: String { "taxCountdown.paidInFull".localized }
    static var taxCountdownOwe: String { "taxCountdown.owe".localized }
    static var taxCountdownPaid: String { "taxCountdown.paid".localized }
    static var taxCountdownPayNow: String { "taxCountdown.payNow".localized }
    static var taxCountdownEstOwed: String { "taxCountdown.estOwed".localized }
    static var taxCountdownDisclaimer: String { "taxCountdown.disclaimer".localized }

    // MARK: - Add Entry
    static var addEntryWhatToAdd: String { "addEntry.whatToAdd".localized }
    static var addEntryRecordEarnings: String { "addEntry.recordEarnings".localized }
    static var addEntryTrackExpense: String { "addEntry.trackExpense".localized }
    static var addEntryLogTrip: String { "addEntry.logTrip".localized }

    // MARK: - Settings
    static var settingsAutoSync: String { "settings.autoSync".localized }
    static var settingsYourProfile: String { "settings.yourProfile".localized }
    static var settingsConnectBank: String { "settings.connectBank".localized }
    static var settingsConnectBankSubtitle: String { "settings.connectBankSubtitle".localized }
    static var settingsConnectPlatforms: String { "settings.connectPlatforms".localized }
    static var settingsConnectPlatformsSubtitle: String { "settings.connectPlatformsSubtitle".localized }
    static var settingsLinkApp: String { "settings.linkApp".localized }
    static var settingsTaxProfile: String { "settings.taxProfile".localized }
    static var settingsFilingStatus: String { "settings.filingStatus".localized }
    static var settingsState: String { "settings.state".localized }
    static var settingsNotifications: String { "settings.notifications".localized }
    static var settingsPushNotifications: String { "settings.pushNotifications".localized }
    static var settingsConnectedPlatforms: String { "settings.connectedPlatforms".localized }
    static var settingsSubscription: String { "settings.subscription".localized }
    static var settingsUpgradePremium: String { "settings.upgradePremium".localized }
    static var settingsVersion: String { "settings.version".localized }
    static var settingsPrivacy: String { "settings.privacy".localized }
    static var settingsTerms: String { "settings.terms".localized }
    static var settingsSupport: String { "settings.support".localized }
    static var settingsSignInToSync: String { "settings.signInToSync".localized }

    // MARK: - Onboarding
    static var onboardingContinue: String { "onboarding.continue".localized }
    static var onboardingAllSet: String { "onboarding.allSet".localized }
    static var onboardingAllSetSubtitle: String { "onboarding.allSetSubtitle".localized }
    static var onboardingGetStarted: String { "onboarding.getStarted".localized }
    static var onboardingTipLogGig: String { "onboarding.tipLogGig".localized }
    static var onboardingTipLogGigDetail: String { "onboarding.tipLogGigDetail".localized }
    static var onboardingTipTrackExpense: String { "onboarding.tipTrackExpense".localized }
    static var onboardingTipTrackExpenseDetail: String { "onboarding.tipTrackExpenseDetail".localized }
    static var onboardingTipLogTrip: String { "onboarding.tipLogTrip".localized }
    static var onboardingTipLogTripDetail: String { "onboarding.tipLogTripDetail".localized }
    static var onboardingProTeaser: String { "onboarding.proTeaser".localized }
    static var onboardingProCTA: String { "onboarding.proCTA".localized }
}

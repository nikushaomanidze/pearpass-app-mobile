//
//  V2HostView.swift
//  PearPassAutoFillExtension
//
//  Root SwiftUI view for the V2 assertion + registration flows
//  (mirror of ExtensionMainView and PasskeyRegistrationView combined).
//  Reuses ExtensionViewModel for auth state and bridges its @Published state
//  to the V2 view bindings.
//

import SwiftUI
import AuthenticationServices

/// iOS-version-agnostic registration context. Lets V2HostView (which targets all
/// iOS versions for assertion) accept registration data without depending on
/// PasskeyRegistrationRequest (iOS 17+).
struct V2RegistrationContext {
    let rpId: String
    let rpName: String
    let userId: Data
    let userName: String
    let userDisplayName: String
    let challenge: Data
}

struct V2HostView: View {

    @StateObject private var viewModel = ExtensionViewModel()
    @State private var vaultClient: PearPassVaultClient?
    @State private var isInitializing: Bool = true
    @State private var initialError: String?

    @State private var credentials: [VaultRecord] = []
    @State private var isLoadingCredentials: Bool = false
    @State private var isVaultDropdownOpen: Bool = false

    // Passkey form state (registration mode only)
    @State private var showPasskeyForm: Bool = false
    @State private var formTitleText: String = ""
    @State private var formUsername: String = ""
    @State private var formPasskeyDate: String = ""
    @State private var formWebsite: String = ""
    @State private var formComment: String = ""
    @State private var formSaveError: String?
    @State private var isSavingPasskey: Bool = false
    @State private var loadedFolders: [String] = []

    let serviceIdentifiers: [ASCredentialServiceIdentifier]
    let presentationWindow: UIWindow?
    var mode: CombinedItemsMode = .assertion
    var registrationContext: V2RegistrationContext? = nil
    let onCancel: () -> Void
    let onComplete: (String, String) -> Void
    var onCompleteRegistration: ((PasskeyCredential, Data, Data) -> Void)? = nil
    let onVaultClientCreated: ((PearPassVaultClient) -> Void)?

    var body: some View {
        ZStack {
            PPColors.surfacePrimary.ignoresSafeArea()

            if isInitializing {
                LoadingV2View()
            } else if let _ = initialError {
                ErrorBoundaryV2View(
                    title: "Autofill Error",
                    subtitle: "Unable to initialize autofill",
                    message: "An unexpected error occurred. Please try again.",
                    onBack: onCancel
                )
            } else if showPasskeyForm {
                passkeyFormView
            } else {
                routedView
            }
        }
        .onAppear { initializeIfNeeded() }
        .animation(.easeInOut(duration: 0.25), value: viewModel.currentFlow)
        .animation(.easeInOut(duration: 0.25), value: isInitializing)
        .animation(.easeInOut(duration: 0.25), value: showPasskeyForm)
    }

    // MARK: - Routing

    @ViewBuilder
    private var routedView: some View {
        switch viewModel.currentFlow {
        case .missingConfiguration:
            MissingConfigurationV2View(onBack: onCancel)

        case .masterPassword:
            MasterPasswordV2View(
                headerTitle: mode == .registration ? "Create Passkey" : "Sign in",
                password: bindingFor(\.masterPassword),
                onClose: onCancel,
                onContinue: handleMasterPasswordContinue
            )

        case .vaultSelection, .vaultPassword, .credentialsList:
            CombinedItemsV2View(
                headerTitle: mode == .registration ? "Create Passkey" : "Sign in",
                mode: mode,
                searchText: bindingFor(\.searchText),
                selectedVaultId: Binding(
                    get: { viewModel.selectedVault?.id },
                    set: { newId in
                        if let id = newId,
                           let vault = viewModel.vaults.first(where: { $0.id == id }) {
                            viewModel.selectVault(vault)
                        }
                    }
                ),
                isVaultDropdownOpen: $isVaultDropdownOpen,
                vaults: viewModel.vaults.map { CombinedVaultOption(id: $0.id, name: $0.name) },
                credentials: filteredCredentials.map { record in
                    CombinedCredentialOption(
                        id: record.id,
                        title: record.data?.title ?? "(Untitled)",
                        username: record.data?.username,
                        initials: initials(for: record.data?.title)
                    )
                },
                isLoading: isLoadingCredentials,
                requiresVaultPassword: false,
                vaultPassword: bindingFor(\.vaultPassword),
                onClose: onCancel,
                onSelectVault: { vaultId in
                    if let vault = viewModel.vaults.first(where: { $0.id == vaultId }) {
                        viewModel.selectVault(vault)
                        isVaultDropdownOpen = false
                    }
                },
                onSelectCredential: handleSelectCredential,
                onAddNewLogin: handleAddNewLogin,
                onUnlockVault: {}
            )
        }
    }

    private var passkeyFormView: some View {
        PasskeyFormV2View(
            headerTitle: "Create Passkey",
            titleText: $formTitleText,
            username: $formUsername,
            passkeyDate: $formPasskeyDate,
            website: $formWebsite,
            comment: $formComment,
            folderName: nil,
            saveError: formSaveError,
            onBack: { showPasskeyForm = false },
            onClose: onCancel,
            onSelectFolder: {},
            onSave: handleFormSave,
            onDiscard: { showPasskeyForm = false }
        )
    }

    // MARK: - Initialization

    private func initializeIfNeeded() {
        guard vaultClient == nil else { return }

        let client = PearPassVaultClient(debugMode: true, readOnly: true)
        vaultClient = client
        onVaultClientCreated?(client)

        Task {
            do {
                try await client.waitForInitialization()
                await initializeUser(client: client)
            } catch {
                await MainActor.run {
                    initialError = String(describing: error)
                    isInitializing = false
                }
            }
        }
    }

    private func initializeUser(client: PearPassVaultClient) async {
        do {
            let vaultsStatusRes = try await client.vaultsGetStatus()
            let masterPasswordEncryption = try await client.getMasterPasswordEncryption(vaultStatus: vaultsStatusRes)

            let passwordSet = masterPasswordEncryption != nil &&
                              masterPasswordEncryption?.ciphertext != nil &&
                              masterPasswordEncryption?.nonce != nil &&
                              masterPasswordEncryption?.salt != nil

            await MainActor.run {
                viewModel.currentFlow = passwordSet ? .masterPassword : .missingConfiguration
                isInitializing = false
            }
        } catch {
            var passwordSet = false
            if let mpe = try? await client.getMasterPasswordEncryption(vaultStatus: nil) {
                passwordSet = mpe.ciphertext != nil && mpe.nonce != nil && mpe.salt != nil
            }
            await MainActor.run {
                viewModel.currentFlow = passwordSet ? .masterPassword : .missingConfiguration
                isInitializing = false
            }
        }
    }

    // MARK: - Auth flow actions

    private func handleMasterPasswordContinue() {
        guard let client = vaultClient else { return }
        let password = viewModel.masterPassword
        guard !password.isEmpty else { return }

        Task {
            do {
                guard let passwordData = password.data(using: .utf8) else { return }
                try await client.initWithPassword(password: passwordData)
                let vaults = try await client.listVaults()
                let folders = (try? await client.listFolders()) ?? []

                await MainActor.run {
                    viewModel.vaults = vaults
                    loadedFolders = folders
                    viewModel.authenticateWithMasterPassword()
                    if let first = vaults.first {
                        viewModel.selectedVault = first
                        viewModel.currentFlow = .credentialsList(vault: first)
                        loadCredentials(for: first)
                    }
                }
            } catch {
                NSLog("[V2HostView] master-password unlock error: \(error)")
            }
        }
    }

    private func handleSelectCredential(_ id: String) {
        guard let record = credentials.first(where: { $0.id == id }) else { return }
        let username = record.data?.username ?? ""
        let password = record.data?.password ?? ""
        onComplete(username, password)
    }

    private func handleAddNewLogin() {
        // Prefill form from registration context when available.
        if let ctx = registrationContext {
            formTitleText = ctx.rpName.isEmpty ? ctx.rpId : ctx.rpName
            formUsername = ctx.userName
            formWebsite = ctx.rpId
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formPasskeyDate = formatter.string(from: Date())
        formSaveError = nil
        showPasskeyForm = true
    }

    // MARK: - Passkey save (registration only) — mirrors V1 handleFormSave.

    private func handleFormSave() {
        guard let ctx = registrationContext,
              let onCompleteRegistration = onCompleteRegistration,
              let client = vaultClient,
              let vault = viewModel.selectedVault else {
            formSaveError = "Missing registration context"
            return
        }
        guard !formTitleText.trimmingCharacters(in: .whitespaces).isEmpty else {
            formSaveError = "Title is required"
            return
        }

        isSavingPasskey = true
        formSaveError = nil

        Task {
            do {
                // 1. Generate passkey crypto.
                let (credential, attestationObject, credentialIdData) = try generatePasskey(ctx: ctx)

                // 2. Hashed password for job-file encryption.
                guard let hashedPassword = await PasskeyJobCreator.getHashedPassword(from: client) else {
                    throw PasskeyJobError.noHashedPassword
                }

                // 3. Build form data + create ADD_PASSKEY job.
                let websites = formWebsite.isEmpty ? [] : [formWebsite]
                let formData = PasskeyFormData(
                    title: formTitleText,
                    username: formUsername,
                    websites: websites,
                    note: formComment,
                    folder: nil,
                    attachments: [],
                    keepAttachmentIds: [],
                    passkeyCreatedAt: Int64(Date().timeIntervalSince1970 * 1000),
                    existingRecord: nil
                )

                _ = try PasskeyJobCreator.createAddPasskeyJob(
                    vaultId: vault.id,
                    credential: credential,
                    formData: formData,
                    rpId: ctx.rpId,
                    rpName: ctx.rpName,
                    userId: ctx.userId.base64URLEncodedString(),
                    userName: ctx.userName,
                    userDisplayName: ctx.userDisplayName,
                    hashedPassword: hashedPassword
                )

                // 4. Hand control back to the system — passkey is ready.
                await MainActor.run {
                    isSavingPasskey = false
                    onCompleteRegistration(credential, attestationObject, credentialIdData)
                }
            } catch {
                NSLog("[V2HostView] Save error: \(error)")
                await MainActor.run {
                    isSavingPasskey = false
                    formSaveError = "Failed to save passkey"
                }
            }
        }
    }

    /// Generates a passkey + authenticator data + attestation object.
    /// Mirrors V1 PasskeyRegistrationView.generatePasskey().
    private func generatePasskey(ctx: V2RegistrationContext) throws -> (PasskeyCredential, Data, Data) {
        let privateKey = PasskeyCrypto.generatePrivateKey()
        let privateKeyB64 = PasskeyCrypto.exportPrivateKey(privateKey)
        guard let privateKeyData = Data(base64URLEncoded: privateKeyB64) else {
            throw PearPassVaultError.unknown("Failed to decode private key")
        }
        let publicKeyB64 = PasskeyCrypto.exportPublicKey(privateKey.publicKey)

        let (credentialIdData, credentialIdB64) = PasskeyCrypto.generateCredentialId()

        let authData = AuthenticatorDataBuilder.buildForRegistration(
            rpId: ctx.rpId,
            credentialId: credentialIdData,
            publicKey: privateKey.publicKey
        )

        let attestationObject = AuthenticatorDataBuilder.encodeAttestationObject(authData: authData)

        let clientDataJSON = AuthenticatorDataBuilder.buildClientDataJSONForRegistration(
            challenge: ctx.challenge,
            origin: "https://\(ctx.rpId)"
        )

        let response = PasskeyResponse(
            clientDataJSON: clientDataJSON.base64URLEncodedString(),
            attestationObject: attestationObject.base64URLEncodedString(),
            authenticatorData: authData.base64URLEncodedString(),
            publicKey: publicKeyB64,
            publicKeyAlgorithm: -7,
            transports: ["internal"]
        )

        let credential = PasskeyCredential.create(
            credentialId: credentialIdB64,
            response: response,
            privateKeyBuffer: privateKeyData,
            userId: ctx.userId.base64URLEncodedString()
        )

        return (credential, attestationObject, credentialIdData)
    }

    // MARK: - Data loading

    /// Mirrors V1 CredentialsListView.loadAllCredentials — opens the vault and
    /// fetches every "record/" entry. Both passwords and passkeys land in the
    /// same combined list for V2.
    private func loadCredentials(for vault: Vault) {
        guard let client = vaultClient else { return }
        Task {
            await MainActor.run { isLoadingCredentials = true }
            do {
                _ = try await client.getVaultById(vaultId: vault.id)
                let records = try await client.activeVaultList(filterKey: "record/")
                await MainActor.run {
                    credentials = records
                    isLoadingCredentials = false
                }
            } catch {
                NSLog("[V2HostView] loadCredentials error: \(error)")
                await MainActor.run {
                    credentials = []
                    isLoadingCredentials = false
                }
            }
        }
    }

    // MARK: - Helpers

    /// Filters loaded vault records to those matching the current site (registration rpId
    /// or assertion serviceIdentifier domain). Mirrors V1 CredentialsListView filtering.
    private var filteredCredentials: [VaultRecord] {
        guard let target = targetDomain else { return credentials }
        return credentials.filter { record in
            let websites = record.data?.websites ?? []
            for site in websites {
                let domain = extractDomain(from: site).lowercased()
                let t = target.lowercased()
                if domain == t || domain.hasSuffix(".\(t)") || t.hasSuffix(".\(domain)") {
                    return true
                }
            }
            return false
        }
    }

    private var targetDomain: String? {
        if let ctx = registrationContext { return ctx.rpId }
        // Assertion: pull domain from first ASCredentialServiceIdentifier.
        if let first = serviceIdentifiers.first {
            return extractDomain(from: first.identifier)
        }
        return nil
    }

    private func extractDomain(from urlOrHost: String) -> String {
        var s = urlOrHost
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        if let colon = s.firstIndex(of: ":") { s = String(s[..<colon]) }
        return s
    }

    private func initials(for title: String?) -> String {
        guard let title = title, !title.isEmpty else { return "?" }
        let words = title.split(separator: " ")
        if words.count >= 2,
           let firstChar = words[0].first,
           let secondChar = words[1].first {
            return String(firstChar).uppercased() + String(secondChar).uppercased()
        }
        return String(title.prefix(2)).uppercased()
    }

    private func bindingFor(_ keyPath: ReferenceWritableKeyPath<ExtensionViewModel, String>) -> Binding<String> {
        Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
    }
}

import SwiftUI

struct LicenseGateView: View {
    var onValidated: () -> Void

    @State private var licenseText = LicenseGateStore.savedLicense()
    @State private var errorMessage: String?
    @State private var isLoading = false
    @AppStorage("keyauth.license.remember") private var rememberLicense = false

    var body: some View {
        ZStack {
            AppTheme.pageBackground
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer(minLength: 10)

                VStack(spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.75, green: 0.45, blue: 0.95), Color(red: 0.55, green: 0.32, blue: 0.82)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 110, height: 110)

                        // Use shared AppLogo so the new BrandLogo asset is used.
                        AppLogo(size: 78)
                    }

                    VStack(spacing: 8) {
                        Text("Baijstore")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundStyle(.primary)

                        Text("Introduce tu clave API para liberar la aplicación.")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14)
                    }
                }

                VStack(spacing: 14) {
                    TextField("Introduce tu licencia", text: $licenseText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.default)
                        .padding(16)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.gray.opacity(0.35), lineWidth: 1)
                                .background(Color.white.opacity(0.18))
                        )
                        .foregroundStyle(.primary)

                    Button {
                        Task { await validateLicense() }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(isLoading ? Color.gray : Color(red: 0.82, green: 0.82, blue: 0.84))
                                .frame(height: 54)

                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            } else {
                                Text("Continuar")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.black)
                            }
                        }
                    }
                    .disabled(isLoading)
                    .frame(maxWidth: .infinity)

                    Toggle(isOn: $rememberLicense) {
                        Text("Recordar licencia en este dispositivo")
                            .font(.system(size: 14))
                    }
                    .padding(.horizontal, 4)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)
                    }
                    let lastResponse = LicenseGateStore.savedLastResponse()
                    if !lastResponse.isEmpty {
                        Text(lastResponse)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)
                    }
                }
                .padding(.horizontal, 22)

                Spacer()
            }
        }
    }

    private func validateLicense() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let response = try await KeyAuthLicenseService.validate(licenseKey: licenseText)

            // If server provides explicit `success`, require it; otherwise rely on response.isValid
            if let explicitSuccess = response.success {
                if explicitSuccess {
                    // Ensure HWID checks: if server reports HWID and it doesn't match, deny
                    if let hwid = response.hwid, !hwid.isEmpty, hwid != KeyAuthConfig.hardwareID() {
                        await MainActor.run {
                            errorMessage = "Licencia en uso en otro dispositivo."
                            isLoading = false
                        }
                        return
                    }

                    await MainActor.run {
                        isLoading = false
                        onValidated()
                    }
                } else {
                    let msg = response.rawText.isEmpty ? response.state.summary : response.rawText
                    await MainActor.run {
                        errorMessage = msg
                        isLoading = false
                    }
                }
            } else if response.isValid {
                // Ensure HWID checks: if server reports HWID and it doesn't match, deny
                if let hwid = response.hwid, !hwid.isEmpty, hwid != KeyAuthConfig.hardwareID() {
                    await MainActor.run {
                        errorMessage = "Licencia en uso en otro dispositivo."
                        isLoading = false
                    }
                    return
                }

                await MainActor.run {
                    isLoading = false
                    onValidated()
                }
            } else {
                let msg = response.rawText.isEmpty ? response.state.summary : response.rawText
                await MainActor.run {
                    errorMessage = msg
                    isLoading = false
                }
            }
        } catch let error as KeyAuthLicenseError {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "No se pudo validar la licencia en este momento."
                isLoading = false
            }
        }
    }
}

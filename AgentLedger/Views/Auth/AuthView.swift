import SwiftUI

struct AuthView: View {
    @EnvironmentObject var amplifyService: AmplifyService
    @State private var isShowingSignUp = false
    @FocusState private var authFieldFocused: Bool

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let isSmall = geo.size.height < 700
                ScrollView {
                    VStack(spacing: isSmall ? 12 : 24) {
                        Spacer().frame(height: isSmall ? 16 : 40)

                        // Logo / branding
                        VStack(spacing: isSmall ? 8 : 16) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: isSmall ? 70 : 100, height: isSmall ? 70 : 100)
                                Image(systemName: "storefront.fill")
                                    .font(.system(size: isSmall ? 30 : 44))
                                    .foregroundStyle(.white)
                            }

                            Text("Marketplace")
                                .font(isSmall ? .title.weight(.bold) : .largeTitle.weight(.bold))

                            Text("Buy & sell locally")
                                .font(isSmall ? .subheadline : .title3)
                                .foregroundStyle(.secondary)
                        }

                        Spacer().frame(height: isSmall ? 8 : 20)

                        // Auth form
                        if isShowingSignUp {
                            SignUpFormView(switchToSignIn: { isShowingSignUp = false })
                        } else {
                            SignInFormView(switchToSignUp: { isShowingSignUp = true })
                        }

                        Spacer().frame(height: isSmall ? 16 : 40)
                    }
                    .padding()
                }
            }
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationBarHidden(true)
        }
        .clearDoneToolbar(
            onClear: { NotificationCenter.default.post(name: .authClearField, object: nil) },
            onDone: { NotificationCenter.default.post(name: .authDismissKeyboard, object: nil) }
        )
    }
}

extension Notification.Name {
    static let authClearField = Notification.Name("authClearField")
    static let authDismissKeyboard = Notification.Name("authDismissKeyboard")
}

// MARK: - Sign In Form
struct SignInFormView: View {
    @EnvironmentObject var amplifyService: AmplifyService
    var switchToSignUp: () -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showResetPassword = false
    @FocusState private var focusedField: Field?

    enum Field { case username, password }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    TextField("Using email as Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .focused($focusedField, equals: .username)
                    if !username.isEmpty {
                        Button { username = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                    if !password.isEmpty {
                        Button { password = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await signIn() }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Sign In")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canSubmit ? Color.accentColor : Color.gray)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canSubmit || isLoading)

            Button {
                showResetPassword = true
            } label: {
                Text("Forgot Password?")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }

            Button {
                switchToSignUp()
            } label: {
                HStack(spacing: 4) {
                    Text("Don't have an account?")
                        .foregroundStyle(.secondary)
                    Text("Sign Up")
                        .fontWeight(.medium)
                        .foregroundStyle(Color.accentColor)
                }
                .font(.subheadline)
            }
        }
        .sheet(isPresented: $showResetPassword) {
            ResetPasswordView(prefillUsername: username)
                .environmentObject(amplifyService)
        }
        .onReceive(NotificationCenter.default.publisher(for: .authClearField)) { _ in
            switch focusedField {
            case .username: username = ""
            case .password: password = ""
            case .none: break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .authDismissKeyboard)) { _ in
            focusedField = nil
        }
    }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty
    }

    private func signIn() async {
        isLoading = true
        errorMessage = nil
        do {
            try await amplifyService.signIn(username: username, password: password)
        } catch {
            errorMessage = "Sign in failed. Check your credentials."
        }
        isLoading = false
    }
}

// MARK: - Sign Up Form
struct SignUpFormView: View {
    @EnvironmentObject var amplifyService: AmplifyService
    var switchToSignIn: () -> Void

    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showConfirmation = false
    @State private var confirmationCode = ""
    @FocusState private var focusedField: Field?

    enum Field { case username, email, password, confirmPassword, code }

    var body: some View {
        VStack(spacing: 16) {
            if showConfirmation {
                confirmationForm
            } else {
                signUpForm
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .authClearField)) { _ in
            switch focusedField {
            case .username: username = ""
            case .email: email = ""
            case .password: password = ""
            case .confirmPassword: confirmPassword = ""
            case .code: confirmationCode = ""
            case .none: break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .authDismissKeyboard)) { _ in
            focusedField = nil
        }
    }

    private var signUpForm: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    TextField("Using email as Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .focused($focusedField, equals: .username)
                    if !username.isEmpty {
                        Button { username = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack {
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .focused($focusedField, equals: .email)
                    if !email.isEmpty {
                        Button { email = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .password)
                    if !password.isEmpty {
                        Button { password = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    SecureField("Confirm password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .confirmPassword)
                    if !confirmPassword.isEmpty {
                        Button { confirmPassword = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if password != confirmPassword && !confirmPassword.isEmpty {
                Text("Passwords don't match")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await signUp() }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Create Account")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canSubmit ? Color.accentColor : Color.gray)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canSubmit || isLoading)

            Button {
                switchToSignIn()
            } label: {
                HStack(spacing: 4) {
                    Text("Already have an account?")
                        .foregroundStyle(.secondary)
                    Text("Sign In")
                        .fontWeight(.medium)
                        .foregroundStyle(Color.accentColor)
                }
                .font(.subheadline)
            }
        }
    }

    private var confirmationForm: some View {
        VStack(spacing: 16) {
            Text("Check your email")
                .font(.headline)
            Text("We sent a confirmation code to \(email)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Image(systemName: "number")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                TextField("Confirmation code", text: $confirmationCode)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .code)
                if !confirmationCode.isEmpty {
                    Button { confirmationCode = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await confirmSignUp() }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Confirm")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(!confirmationCode.isEmpty ? Color.accentColor : Color.gray)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(confirmationCode.isEmpty || isLoading)
        }
    }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        password.count >= 8 &&
        password == confirmPassword
    }

    private func signUp() async {
        isLoading = true
        errorMessage = nil
        do {
            try await amplifyService.signUp(username: username, password: password, email: email)
            showConfirmation = true
        } catch {
            errorMessage = "Sign up failed. Try a different username."
        }
        isLoading = false
    }

    private func confirmSignUp() async {
        isLoading = true
        errorMessage = nil
        do {
            try await amplifyService.confirmSignUp(username: username, code: confirmationCode)
            // Auto sign in after confirmation
            try await amplifyService.signIn(username: username, password: password)
        } catch {
            errorMessage = "Invalid code. Please try again."
        }
        isLoading = false
    }
}

// MARK: - Reset Password View
struct ResetPasswordView: View {
    @EnvironmentObject var amplifyService: AmplifyService
    @Environment(\.dismiss) var dismiss

    var prefillUsername: String

    @State private var username = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showCodeEntry = false
    @State private var resetComplete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if resetComplete {
                        completedView
                    } else if showCodeEntry {
                        codeEntryView
                    } else {
                        requestCodeView
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            username = prefillUsername
        }
    }

    // Step 1: Enter username and request code
    private var requestCodeView: some View {
        VStack(spacing: 16) {
            Text("Enter your username and we'll send a reset code to your email.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Image(systemName: "person.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .autocapitalization(.none)
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await requestCode() }
            } label: {
                HStack {
                    if isLoading { ProgressView().tint(.white) }
                    Text("Send Reset Code")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(!username.isEmpty ? Color.accentColor : Color.gray)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(username.isEmpty || isLoading)
        }
    }

    // Step 2: Enter code and new password
    private var codeEntryView: some View {
        VStack(spacing: 16) {
            Text("Enter the code sent to your email and choose a new password.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Image(systemName: "number")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                TextField("Reset code", text: $code)
                    .keyboardType(.numberPad)
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                SecureField("New password", text: $newPassword)
                    .textContentType(.newPassword)
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                SecureField("Confirm new password", text: $confirmPassword)
                    .textContentType(.newPassword)
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if newPassword != confirmPassword && !confirmPassword.isEmpty {
                Text("Passwords don't match")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await confirmReset() }
            } label: {
                HStack {
                    if isLoading { ProgressView().tint(.white) }
                    Text("Reset Password")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canConfirm ? Color.accentColor : Color.gray)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canConfirm || isLoading)
        }
    }

    // Step 3: Success
    private var completedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Password Reset!")
                .font(.title2.weight(.bold))

            Text("You can now sign in with your new password.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                dismiss()
            } label: {
                Text("Back to Sign In")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var canConfirm: Bool {
        !code.isEmpty && newPassword.count >= 8 && newPassword == confirmPassword
    }

    private func requestCode() async {
        isLoading = true
        errorMessage = nil
        do {
            try await amplifyService.resetPassword(for: username.trimmingCharacters(in: .whitespaces))
            showCodeEntry = true
        } catch {
            print("[RESET-PW] Error: \(error)")
            errorMessage = "This email address is not associated with an account. Please check and try again."
        }
        isLoading = false
    }

    private func confirmReset() async {
        isLoading = true
        errorMessage = nil
        do {
            try await amplifyService.confirmResetPassword(for: username, newPassword: newPassword, code: code)
            resetComplete = true
        } catch {
            errorMessage = "Reset failed. Check your code and try again."
        }
        isLoading = false
    }
}

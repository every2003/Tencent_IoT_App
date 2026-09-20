import SwiftUI
import TXLiteAVSDK_IOT

struct DevicePropertiesView: View {
    let device: Device
    @Environment(\.dismiss) var dismiss

    @State private var propertiesJson: String = ""
    @State private var isLoadingProps = false
    @State private var aliasName: String = ""
    @State private var isSavingAlias = false
    @State private var toastMessage: String?
    @State private var showAliasEditor = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.bgColor.ignoresSafeArea()
                propertiesScrollView
            }
            .navigationTitle(L("Device Properties"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L("Close")) { dismiss() }
                }
            }
            .onAppear {
                aliasName = device.name
                loadProperties()
            }
            .overlay(toastOverlayView)
            .appToast(message: $toastMessage)
        }
        .preferredColorScheme(.light)
    }

    private var propertiesScrollView: some View {
        ScrollView {
            VStack(spacing: 16) {
                aliasCard
                propertiesCard
                basicInfoCard
            }
            .padding(.top, 16)
        }
    }

    // MARK: - 别名卡片

    private var aliasCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeaderView(title: L("Device Alias"), icon: "pencil.circle.fill")
            HStack(spacing: 12) {
                TextField(L("Enter device alias"), text: $aliasName)
                    .font(.system(size: 15))
                    .foregroundColor(.textPrimary)
                    .autocorrectionDisabled()
                aliasSaveButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var aliasSaveButton: some View {
        if isSavingAlias {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .primaryColor))
                .scaleEffect(0.85)
        } else {
            Button(action: saveAliasName) {
                Text(L("Save"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        aliasName.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.primaryColor.opacity(0.4)
                            : Color.primaryColor
                    )
                    .cornerRadius(6)
            }
            .disabled(aliasName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - 属性卡片

    private var propertiesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionHeaderView(title: L("Device Properties"), icon: "list.bullet.rectangle.fill")
                Spacer()
                Button(action: loadProperties) {
                    HStack(spacing: 4) {
                        if isLoadingProps {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .primaryColor))
                                .scaleEffect(0.75)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13))
                                .foregroundColor(.primaryColor)
                        }
                        Text(L("Refresh"))
                            .font(.system(size: 13))
                            .foregroundColor(.primaryColor)
                    }
                }
                .padding(.trailing, 16)
                .padding(.top, 14)
            }
            propertiesContent
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var propertiesContent: some View {
        if propertiesJson.isEmpty && !isLoadingProps {
            HStack {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.textDisabled)
                    Text(L("Tap refresh to get device properties"))
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                }
                .padding(.vertical, 30)
                Spacer()
            }
        } else {
            Text(formattedJson(propertiesJson))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .textSelection(.enabled)
        }
    }

    // MARK: - 基本信息卡片

    private var basicInfoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeaderView(title: L("Basic Info"), icon: "info.circle.fill")
            PropertyInfoRow(label: L("Product ID"), value: device.productId)
            Divider().padding(.leading, 16)
            PropertyInfoRow(label: L("Device Name"), value: device.deviceName)
            Divider().padding(.leading, 16)
            PropertyInfoRow(label: L("Display Name"), value: device.name)
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }

    private var toastOverlayView: some View {
        EmptyView()
    }

    // MARK: - 数据操作

    private func loadProperties() {
        guard let deviceManager = TXIoTEngine.getInstance().getDeviceManager() else {
            showToast(L("Not logged in or failed to get DeviceManager"))
            return
        }
        let did = TXIoTDeviceId()
        did.productId = device.productId
        did.deviceName = device.deviceName
        isLoadingProps = true

        let cb = TXIoTCallback<NSString>()
        cb.onSuccess = { result in self.onLoadPropertiesSuccess(result) }
        cb.onError = { errorCode, errorMessage in
            DispatchQueue.main.async {
                isLoadingProps = false
                showToast(L("Failed to get properties: %@", "\(errorMessage ?? "")"))
            }
        }
        deviceManager.getProperties(did, callback: cb)
    }

    private func onLoadPropertiesSuccess(_ result: NSString?) {
        DispatchQueue.main.async {
            isLoadingProps = false
            propertiesJson = (result as String?) ?? ""
        }
    }

    private func saveAliasName() {
        let name = aliasName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        guard let deviceManager = TXIoTEngine.getInstance().getDeviceManager() else {
            showToast(L("Not logged in or failed to get DeviceManager"))
            return
        }
        let did = TXIoTDeviceId()
        did.productId = device.productId
        did.deviceName = device.deviceName
        isSavingAlias = true

        let cb = TXIoTVoidCallback()
        cb.onSuccess = { self.onSaveAliasSuccess(name) }
        cb.onError = { errorCode, errorMessage in
            DispatchQueue.main.async {
                isSavingAlias = false
                showToast(L("Modify failed: %@", "\(errorMessage ?? "")"))
            }
        }
        deviceManager.modifyAliasName(did, aliasName: name, callback: cb)
    }

    private func onSaveAliasSuccess(_ name: String) {
        DispatchQueue.main.async {
            isSavingAlias = false
            showToast(L("Alias updated to \"%@\"", "\(name)"))
        }
    }

    private func formattedJson(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
            let str = String(data: pretty, encoding: .utf8)
        else {
            return raw
        }
        return str
    }

    private func showToast(_ msg: String) {
        withAnimation { toastMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { toastMessage = nil }
        }
    }
}

// MARK: - 子组件

private struct PropertyInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .frame(width: 80, alignment: .leading)
            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 14))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

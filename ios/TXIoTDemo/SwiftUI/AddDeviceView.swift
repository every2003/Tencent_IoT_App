import SwiftUI

struct AddDeviceView: View {
    @EnvironmentObject var deviceViewModel: DeviceViewModel
    @Environment(\.dismiss) var dismiss

    @State private var productId = ""
    @State private var deviceName = ""
    @State private var deviceSignature = ""

    @State private var familyList: [FamilyItem] = []
    @State private var selectedFamilyId = ""
    @State private var selectedFamilyName = L("Select Family")
    @State private var showFamilyPicker = false
    @State private var isLoadingFamilies = false

    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isLoading = false
    @State private var showScanner = false
    @State private var showUnsavedAlert = false

    var body: some View {
        VStack(spacing: 0) {
            gradientHeader

            ScrollView {
                formContent
            }
            .background(Color.white)
        }
        .background(Color.white.ignoresSafeArea())
        .alert(alertMessage, isPresented: $showAlert) {
            Button(L("OK"), role: .cancel) {}
        }
        .alert(L("Notice"), isPresented: $showUnsavedAlert) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("OK")) {
                dismiss()
            }
        } message: {
            Text(L("The current page has unsaved changes. Are you sure you want to leave?"))
        }
        .sheet(isPresented: $showScanner) {
            QRCodeScannerView { scanResult in
                handleScanResult(scanResult)
            }
        }
        .sheet(isPresented: $showFamilyPicker) {
            familyPickerSheet
        }
        .onAppear {
            loadFamilyList()
        }
    }

    // MARK: - 渐变 Header
    // 固定高度 96pt（状态栏 + 工具栏），HStack 垂直居中
    private var gradientHeader: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.gradientStart, Color.gradientEnd]),
                startPoint: UnitPoint(x: 0, y: 0),
                endPoint: UnitPoint(x: 1, y: 1)
            )
            .ignoresSafeArea(edges: .top)

            HStack {
                Button(action: handleBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
                .contentShape(Rectangle())

                Spacer()

                Text(L("Add Device"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                Color.clear
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 48)
    }

    // MARK: - 表单内容
    private var formContent: some View {
        VStack(spacing: 0) {
            scanArea
            dividerSection
            manualInputForm
            addButton
            Spacer(minLength: 24)
        }
        .padding(.horizontal, 28)
    }

    private var scanArea: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    .foregroundColor(Color(white: 0.4))

                scanAreaHint
                    .padding(16)
            }
            .frame(width: 150, height: 150)
            .onTapGesture {
                showScanner = true
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private var scanAreaHint: some View {
        VStack(spacing: 14) {
            Image(systemName: "qrcode")
                .font(.system(size: 72))
                .foregroundColor(.primaryColor)

            Text(L("Scan Device QR Code"))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.textPrimary)
        }
    }

    private var dividerSection: some View {
        HorizontalDivider(text: L("Or enter manually"))
            .padding(.vertical, 16)
    }

    private var manualInputForm: some View {
        VStack(spacing: 0) {
            PickerField(
                label: L("🏠 Bind Family"),
                placeholder: L("Select Family"),
                selectedText: selectedFamilyName,
                actionLabel: L("Switch"),
                action: {
                    if familyList.isEmpty {
                        alertMessage = L("No family yet. Please create one in the device list first.")
                        showAlert = true
                    } else {
                        showFamilyPicker = true
                    }
                },
                disabled: isLoading
            )
            .padding(.bottom, 16)

            LabeledTextField(
                label: L("Signature"),
                placeholder: L("Please enter signature"),
                text: $deviceSignature,
                icon: "signature"
            )
            .padding(.bottom, 28)
        }
    }

    // MARK: - 家庭选择弹窗（对齐 DeviceListView familySwitchSheetContent + CommonBottomSheet）
    @ViewBuilder
    private var familyPickerSheet: some View {
        let rowHeight: CGFloat = 60
        let headerFooter: CGFloat = 155
        let familyHeight = CGFloat(max(familyList.count, 1)) * rowHeight + headerFooter

        CommonBottomSheet(
            title: L("🏠 Select Family"),
            hint: L("Current: %@", "\(selectedFamilyName)"),
            confirmTitle: nil,
            cancelTitle: L("Cancel"),
            sheetHeight: min(familyHeight, 420),
            onCancel: { showFamilyPicker = false }
        ) {
            if familyList.isEmpty {
                Text(L("No family yet. Please create one in the device list first."))
                    .font(.system(size: 16))
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 0) {
                    ForEach(familyList) { family in
                        FamilySwitchRow(
                            family: family,
                            isCurrent: family.id == selectedFamilyId,
                            onTap: {
                                showFamilyPicker = false
                                selectFamily(id: family.id, name: family.name)
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - 添加按钮
    private var addButton: some View {
        PrimaryButton(
            title: isLoading ? L("Adding...") : L("Add Device"),
            action: handleAddDevice,
            isLoading: isLoading
        )
        .padding(.top, 8)
    }

    private func loadFamilyList() {
        isLoadingFamilies = true
        DeviceAPIBridge.getFamilyList { success, familyList, errorMsg in
            let items: [FamilyItem]
            if success, let familyList = familyList, !familyList.isEmpty {
                items = familyList.compactMap { dict -> FamilyItem? in
                    guard let fid = dict["FamilyId"] as? String,
                          let name = dict["Name"] as? String
                    else { return nil }
                    return FamilyItem(id: fid, name: name)
                }
            } else {
                items = []
            }
            DispatchQueue.main.async {
                isLoadingFamilies = false
                if !items.isEmpty {
                    self.familyList = items
                    self.selectDefaultFamily(from: items)
                } else {
                    self.familyList = []
                    self.selectedFamilyId = ""
                    self.selectedFamilyName = L("No family yet. Please create one in the device list first.")
                }
            }
        }
    }

    private func selectDefaultFamily(from families: [FamilyItem]) {
        guard let first = families.first else { return }
        selectFamily(id: first.id, name: first.name)
    }

    private func selectFamily(id: String, name: String) {
        selectedFamilyId = id
        selectedFamilyName = name
        // 同步设置当前家庭 ID 到 OC 桥接层（bindDevice 内部会使用它）
        DeviceAPIBridge.currentFamilyId = id
    }

    private func handleBack() {
        if hasUnsavedInput() {
            showUnsavedAlert = true
        } else {
            dismiss()
        }
    }

    private func hasUnsavedInput() -> Bool {
        return !productId.isEmpty || !deviceName.isEmpty || !deviceSignature.isEmpty
    }

    func handleScanResult(_ scanResult: String) {
        guard let jsonData = scanResult.data(using: .utf8) else {
            alertMessage = L("Invalid QR code data")
            showAlert = true
            return
        }

        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(
                with: jsonData,
                options: []
            ) as? [String: Any] else {
                alertMessage = L("QR code format error: unable to parse JSON")
                showAlert = true
                return
            }
            json = parsed
        } catch {
            alertMessage = L("QR code format error: %@", "\(error.localizedDescription)")
            showAlert = true
            return
        }

        applyScanFields(from: json)
    }

    // 将扫描 JSON 字段填入表单
    private func applyScanFields(from json: [String: Any]) {
        var hasValidData = false
        if let pid = json["ProductId"] as? String {
            productId = pid
            hasValidData = true
        }
        if let dName = json["DeviceName"] as? String {
            deviceName = dName
            hasValidData = true
        }
        if let sig = json["Signature"] as? String {
            deviceSignature = sig
            hasValidData = true
        }
        if !hasValidData {
            alertMessage = L("QR code format error: no valid fields found")
            showAlert = true
        }
    }

    func handleAddDevice() {
        let signature = deviceSignature.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !signature.isEmpty else {
            alertMessage = L("Please scan the QR code")
            showAlert = true
            return
        }

        // 验证：必须选择家庭
        guard !selectedFamilyId.isEmpty else {
            alertMessage = L("Please select a family first")
            showAlert = true
            return
        }

        isLoading = true

        let familyName = selectedFamilyName
        let viewModel = deviceViewModel

        DeviceManager.shared.bindDevice(
            withSignature: signature
        ) {
            success,
            message in
            Task { @MainActor in
                handleBindDeviceResult(
                    success: success,
                    message: message,
                    familyName: familyName,
                    viewModel: viewModel
                )
            }
        }
    }

    // MARK: - 绑定结果处理（提取自 handleAddDevice 回调解耦缩进层级）
    private func handleBindDeviceResult(
        success: Bool,
        message: String?,
        familyName: String,
        viewModel: DeviceViewModel
    ) {
        isLoading = false
        if success {
            alertMessage = L("Bound to [%@] successfully", "\(familyName)")
            showAlert = true
            viewModel.refreshDevicesAfterBindSuccess {
                dismiss()
            }
        } else {
            alertMessage = message ?? L("Failed to add device. Please try again.")
            showAlert = true
        }
    }
}

#Preview {
    AddDeviceView()
        .environmentObject(DeviceViewModel())
}

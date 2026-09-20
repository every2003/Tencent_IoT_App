import AVFoundation
import SwiftUI

// MARK: - 二维码扫描器视图
struct QRCodeScannerView: View {
    @Environment(\.dismiss) var dismiss
    @State private var showAlert = false
    @State private var alertMessage = ""

    var onScanSuccess: (String) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            QRCodeScannerViewController(
                onScanSuccess: { result in
                    onScanSuccess(result)
                    dismiss()
                },
                onError: { error in
                    alertMessage = error
                    showAlert = true
                }
            )
            .edgesIgnoringSafeArea(.all)

            scanOverlay

            topBar
        }
        .navigationBarHidden(true)
        .alert(alertMessage, isPresented: $showAlert) {
            Button(L("OK"), role: .cancel) {
                dismiss()
            }
        }
    }

    // MARK: - 扫描框与提示
    private var scanOverlay: some View {
        VStack {
            Spacer()

            scanBox

            Text(L("Place the QR code in the frame to scan automatically"))
                .font(.system(size: 14))
                .foregroundColor(.white)
                .padding(.top, 30)

            Spacer()
        }
    }

    private var scanBox: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 四个角的装饰
            cornerDecorations
        }
        .frame(width: 250, height: 250)
    }

    // 四个角的装饰
    private var cornerDecorations: some View {
        VStack {
            HStack {
                ScannerCorner(position: .topLeft)
                Spacer()
                ScannerCorner(position: .topRight)
            }
            Spacer()
            HStack {
                ScannerCorner(position: .bottomLeft)
                Spacer()
                ScannerCorner(position: .bottomRight)
            }
        }
        .frame(width: 250, height: 250)
    }

    // MARK: - 顶部导航栏（对齐 AddDeviceView 渐变 Header）
    private var topBar: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.gradientStart, Color.gradientEnd]),
                startPoint: UnitPoint(x: 0, y: 0),
                endPoint: UnitPoint(x: 1, y: 1)
            )
            .ignoresSafeArea(edges: .top)

            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
                .contentShape(Rectangle())

                Spacer()

                Text(L("Scan QR Code"))
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
}

// MARK: - 扫描框角装饰
struct ScannerCorner: View {
    enum Position {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    let position: Position

    var body: some View {
        ZStack {
            switch position {
            case .topLeft:
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().fill(Color.green).frame(width: 30, height: 4)
                    Rectangle().fill(Color.green).frame(width: 4, height: 30)
                }
            case .topRight:
                VStack(alignment: .trailing, spacing: 0) {
                    Rectangle().fill(Color.green).frame(width: 30, height: 4)
                    Rectangle().fill(Color.green).frame(width: 4, height: 30)
                }
            case .bottomLeft:
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().fill(Color.green).frame(width: 4, height: 30)
                    Rectangle().fill(Color.green).frame(width: 30, height: 4)
                }
            case .bottomRight:
                VStack(alignment: .trailing, spacing: 0) {
                    Rectangle().fill(Color.green).frame(width: 4, height: 30)
                    Rectangle().fill(Color.green).frame(width: 30, height: 4)
                }
            }
        }
    }
}

// MARK: - UIKit 相机控制器包装
struct QRCodeScannerViewController: UIViewControllerRepresentable {
    var onScanSuccess: (String) -> Void
    var onError: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onScanSuccess = onScanSuccess
        controller.onError = onError
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {
        // 不需要更新
    }
}

// MARK: - 实际的相机扫描控制器
@MainActor
class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var onScanSuccess: ((String) -> Void)?
    var onError: ((String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if captureSession?.isRunning == false {
            // AVCaptureSession 的启停本就应在后台线程执行，捕获标记 nonisolated(unsafe)
            nonisolated(unsafe) let session = captureSession
            DispatchQueue.global(qos: .userInitiated).async {
                session?.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if captureSession?.isRunning == true {
            nonisolated(unsafe) let session = captureSession
            DispatchQueue.global(qos: .userInitiated).async {
                session?.stopRunning()
            }
        }
    }

    func setupCamera() {
        // 检查相机权限
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    if granted {
                        self?.setupCaptureSession()
                    } else {
                        self?.onError?(L("Camera permission is required to scan QR codes"))
                    }
                }
            }
        case .denied, .restricted:
            onError?(L("Camera permission denied. Please enable it in Settings."))
        @unknown default:
            onError?(L("Unknown camera permission status"))
        }
    }

    func setupCaptureSession() {
        captureSession = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            onError?(L("Unable to access camera"))
            return
        }

        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            onError?(L("Unable to create video input: %@", "\(error.localizedDescription)"))
            return
        }

        if captureSession?.canAddInput(videoInput) == true {
            captureSession?.addInput(videoInput)
        } else {
            onError?(L("Unable to add video input"))
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if captureSession?.canAddOutput(metadataOutput) == true {
            captureSession?.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            onError?(L("Unable to add metadata output"))
            return
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        previewLayer?.frame = view.layer.bounds
        previewLayer?.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer!)

        nonisolated(unsafe) let session = captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            session?.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate
    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let metadataObject = metadataObjects.first,
            let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
            let stringValue = readableObject.stringValue
        else { return }

        Task { @MainActor [weak self] in
            self?.captureSession?.stopRunning()
            // 震动反馈
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            // 回调扫描结果
            self?.onScanSuccess?(stringValue)
        }
    }
}

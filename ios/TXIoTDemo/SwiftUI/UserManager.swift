import Foundation
import SwiftUI
import Combine
import CommonCrypto
import CoreTelephony

@MainActor
@objc class UserManager: NSObject, ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var currentUsername: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    @objc var loginSuccessCallback: (() -> Void)?
    @objc var logoutCallback: (() -> Void)?
    
    /// 登录完成回调（内部使用，登录流程中临时持有）
    private var loginCompletion: ((Bool, String?) -> Void)?
    
    /// 网络权限监听（用于首次安装时网络授权弹窗场景）
    private var cellularData: CTCellularData?
    /// 是否正在等待网络权限恢复后重试
    private var pendingRetry: Bool = false
    /// 暂存登录参数，用于网络恢复后重试
    private var pendingAppKey: String = ""
    private var pendingAppSecret: String = ""
    private var pendingUserId: String = ""
    
    override init() {
        super.init()
        // 完全依赖 SDK 判断登录状态
        if let userInfo = TXIoTEngine.getInstance().getLoginUserInfo() {
            self.currentUsername = userInfo.userId
            self.isLoggedIn = true
        }
        // 监听 AppDelegate 发送的登录状态通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLoginSuccess),
            name: NSNotification.Name("TXIoTLoginSuccess"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLoginFailure(_:)),
            name: NSNotification.Name("TXIoTLoginFailure"),
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - 判断登录是否有效，供 OC 调用
    /// 完全依赖 SDK 判断：getLoginUserInfo 返回非 nil 即为已登录。
    /// 若签名已过期，SDK 会通过 onUserSignatureExpired 回调通知。
    @objc static func checkLoginValid() -> Bool {
        return TXIoTEngine.getInstance().getLoginUserInfo() != nil
    }
    
    // MARK: - 登录（直接调用 SDK login 接口）
    /// 构造 TXIoTUserSignature 并调用 SDK login 接口
    /// - Parameters:
    ///   - appKey: 物联网平台 App Key
    ///   - appSecret: 物联网平台 App Secret（用于生成签名）
    ///   - userId: 用户ID
    ///   - completion: 完成回调，登录结果通过 SDK delegate 异步返回
    func login(appKey: String, appSecret: String, userId: String, completion: @escaping (Bool, String?) -> Void) {
        guard !appKey.isEmpty, !appSecret.isEmpty, !userId.isEmpty else {
            completion(false, L("AppKey, AppSecret and UserId cannot be empty"))
            return
        }
        
        isLoading = true
        errorMessage = nil
        loginCompletion = completion
        
        let userSignature = TXIoTUserSignature()
        userSignature.requestId = UUID().uuidString
        userSignature.timestamp = Int64(Date().timeIntervalSince1970)
        userSignature.nonce = Int.random(in: 1...Int(Int32.max))
        
        var signParams: [String: Any] = [:]
        signParams["OpenID"] = userId
        signParams["AppKey"] = appKey
        signParams["RequestId"] = userSignature.requestId
        signParams["Timestamp"] = userSignature.timestamp
        signParams["Nonce"] = userSignature.nonce
        
        let sortedQuery = createSortedQueryString(signParams)
        guard let signature = signMessage(sortedQuery, withSecret: appSecret) else {
            isLoading = false
            loginCompletion = nil
            completion(false, L("Failed to generate signature"))
            return
        }
        
        userSignature.signature = signature
        
        // 暂存登录参数，用于网络权限恢复后重试
        pendingAppKey = appKey
        pendingAppSecret = appSecret
        pendingUserId = userId
        
        TXIoTEngine.getInstance().login(appKey, userId: userId, userSignature: userSignature)
    }
    
    // MARK: - OC调用此方法设置登录成功
    @objc func setLoginSuccess(username: String) {
        self.currentUsername = username
        self.isLoggedIn = true
    }
    
    // MARK: - 登出
    func logout() {
        self.isLoggedIn = false
        self.currentUsername = ""
        TXIoTEngine.getInstance().logout()
        self.logoutCallback?()
    }
    
    // MARK: - 获取当前登录用户信息
    var currentUserInfo: TXIoTUserInfo? {
        return TXIoTEngine.getInstance().getLoginUserInfo()
    }
    
    // MARK: - 签名工具方法
    
    /// 将参数按 key 字典序排序后拼接为 query string
    private func createSortedQueryString(_ params: [String: Any]) -> String {
        let sortedKeys = params.keys.sorted()
        return sortedKeys.map { "\($0)=\(params[$0]!)" }.joined(separator: "&")
    }
    
    /// HMAC-SHA1 签名，结果 Base64 编码
    private func signMessage(_ message: String, withSecret secret: String) -> String? {
        guard let keyData = secret.cString(using: .ascii),
              let messageData = message.cString(using: .ascii) else {
            return nil
        }
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1),
               keyData, strlen(keyData),
               messageData, strlen(messageData),
               &hmac)
        return Data(hmac).base64EncodedString()
    }
    
    // MARK: - 处理 AppDelegate 的登录通知
    
    @objc private func handleLoginSuccess() {
        self.isLoading = false
        if let userInfo = TXIoTEngine.getInstance().getLoginUserInfo() {
            self.currentUsername = userInfo.userId
        }
        self.isLoggedIn = true
        self.loginCompletion?(true, nil)
        self.loginCompletion = nil
        self.loginSuccessCallback?()
    }
    
    @objc private func handleLoginFailure(_ notification: Notification) {
        self.isLoading = false
        let errorCode = notification.userInfo?["errorCode"] as? Int ?? -1
        let errorMessage = notification.userInfo?["errorMessage"] as? String ?? L("Unknown error")
        let msg = L("Login failed: %@ (code: %@)", "\(errorMessage)", "\(errorCode)")
        self.errorMessage = msg
        
        // 仅当网络权限确实受限时（首次安装未授权场景），才启动监听等待用户授权后重试
        // 其他所有错误（参数无效、鉴权失败等）一律不重试
        if !pendingRetry && !pendingAppKey.isEmpty && isCellularRestricted() {
            startCellularDataMonitor()
        } else {
            if !isCellularRestricted() {
                NSLog("Network not restricted, not a network-permission error, no retry (code: \(errorCode))")
            }
            self.loginCompletion?(false, msg)
            self.loginCompletion = nil
            clearPendingParams()
        }
    }
    
    // MARK: - 网络权限监听（首次安装授权场景）
    
    /// 启动 CTCellularData 监听，当网络权限从受限变为不受限时自动重试登录
    private func startCellularDataMonitor() {
        pendingRetry = true
        cellularData = CTCellularData()
        cellularData?.cellularDataRestrictionDidUpdateNotifier = { [weak self] state in
            guard let self = self else { return }
            // 在闭包线程上立即判断，避免多个 Task 同时入队
            guard self.pendingRetry else {
                NSLog("Already retrying or listening stopped, skip this callback")
                return
            }
            Task { @MainActor [weak self] in
                guard let self = self, self.pendingRetry else { return }
                
                switch state {
                case .notRestricted:
                    // 网络权限已授予，自动重试登录
                    NSLog("Network permission granted, auto retrying login")
                    self.stopCellularDataMonitor()
                    self.retryLogin()
                case .restricted:
                    // 网络仍受限，继续等待（用户可能还没点允许）
                    NSLog("Network permission still restricted, waiting for user authorization...")
                case .restrictedStateUnknown:
                    break
                @unknown default:
                    break
                }
            }
        }
        
        // 设置超时：5秒后如果还没恢复，就放弃重试，返回失败
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self, self.pendingRetry else { return }
            NSLog("Network permission watch timed out, giving up retry")
            self.stopCellularDataMonitor()
            let msg = self.errorMessage ?? L("Login failed: network timeout")
            self.loginCompletion?(false, msg)
            self.loginCompletion = nil
            self.clearPendingParams()
        }
    }
    
    /// 停止 CTCellularData 监听
    private func stopCellularDataMonitor() {
        pendingRetry = false
        cellularData?.cellularDataRestrictionDidUpdateNotifier = nil
        cellularData = nil
    }
    
    /// 网络权限恢复后重试登录
    private func retryLogin() {
        // 防止多个回调同时触发重试
        guard pendingRetry == false else { return }
        
        guard !pendingAppKey.isEmpty, !pendingAppSecret.isEmpty, !pendingUserId.isEmpty else {
            self.loginCompletion?(false, L("Retry parameters lost"))
            self.loginCompletion = nil
            clearPendingParams()
            return
        }
        
        self.isLoading = true
        self.errorMessage = nil
        
        NSLog("Network permission restored, retrying login")
        
        // 重新构造签名（因为 timestamp 和 nonce 需要更新）
        let userSignature = TXIoTUserSignature()
        userSignature.requestId = UUID().uuidString
        userSignature.timestamp = Int64(Date().timeIntervalSince1970)
        userSignature.nonce = Int.random(in: 1...Int(Int32.max))
        
        var signParams: [String: Any] = [:]
        signParams["OpenID"] = pendingUserId
        signParams["AppKey"] = pendingAppKey
        signParams["RequestId"] = userSignature.requestId
        signParams["Timestamp"] = userSignature.timestamp
        signParams["Nonce"] = userSignature.nonce
        
        let sortedQuery = createSortedQueryString(signParams)
        guard let signature = signMessage(sortedQuery, withSecret: pendingAppSecret) else {
            isLoading = false
            self.loginCompletion?(false, L("Retry signature generation failed"))
            self.loginCompletion = nil
            clearPendingParams()
            return
        }
        
        userSignature.signature = signature
        TXIoTEngine.getInstance().login(pendingAppKey, userId: pendingUserId, userSignature: userSignature)
    }

    /// 检查蜂窝网络是否处于受限状态（首次安装未授权网络权限场景）
    private func isCellularRestricted() -> Bool {
        let data = CTCellularData()
        return data.restrictedState == .restricted
    }
    
    /// 清除暂存的登录参数
    private func clearPendingParams() {
        pendingAppKey = ""
        pendingAppSecret = ""
        pendingUserId = ""
    }
}

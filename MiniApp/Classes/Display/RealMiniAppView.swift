import WebKit

internal class RealMiniAppView: UIView, URLSessionDelegate {

    internal var webView: WKWebView
    internal var miniAppTitle: String
    internal var navBar: (UIView & MiniAppNavigationDelegate)?
    internal var webViewBottomConstraintStandalone: NSLayoutConstraint?
    internal var webViewBottomConstraintWithNavBar: NSLayoutConstraint?
    internal var navBarVisibility: MiniAppNavigationVisibility
    internal var isNavBarCustom = false

    internal weak var hostAppMessageDelegate: MiniAppMessageProtocol?
    var localServer: LocalServer?

    internal weak var navigationDelegate: MiniAppNavigationDelegate?

    init(
        miniAppId: String,
        versionId: String,
        miniAppTitle: String,
        hostAppMessageDelegate: MiniAppMessageProtocol,
        displayNavBar: MiniAppNavigationVisibility = .never,
        navigationDelegate: MiniAppNavigationDelegate? = nil,
        navigationView: (UIView & MiniAppNavigationDelegate)? = nil) {

        self.miniAppTitle = miniAppTitle
        webView = MiniAppWebView(miniAppId: miniAppId, versionId: versionId)
        self.hostAppMessageDelegate = hostAppMessageDelegate
        navBarVisibility = displayNavBar
        localServer = LocalServer()
        localServer?.startServer(appId: miniAppId, versionId: versionId, isSecure: true)
        super.init(frame: .zero)
        webView.navigationDelegate = self

        if navBarVisibility != .never {
            if let nav = navigationView {
                navBar = nav
                isNavBarCustom = true
            } else {
                navBar = MiniAppNavigationBar(frame: .zero)
            }
        }
        navBar?.miniAppNavigation(delegate: self)
        webView.configuration.userContentController.addMiniAppScriptMessageHandler(delegate: self, hostAppMessageDelegate: hostAppMessageDelegate)
        webView.configuration.userContentController.addBridgingJavaScript()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.navigationDelegate = navigationDelegate
        addSubview(webView)
        loadWebpage(versionId: versionId)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.layoutAttachTop()
        webViewBottomConstraintStandalone = webView.layoutAttachBottom()
        webView.layoutAttachLeading()
        webView.layoutAttachTrailing()
        if !isNavBarCustom {
            webViewBottomConstraintWithNavBar = navBar?.layoutAttachTop(to: webView)
            webViewBottomConstraintStandalone?.isActive = false
        }
    }

    required init?(coder: NSCoder) {
        return nil
    }
  
    override func removeFromSuperview() {
        localServer?.stopServer()
        localServer = nil
        super.removeFromSuperview()
    }

    func loadWebpage(versionId: String) {
        guard let serverUrl = localServer?.serverURL().absoluteString else {
            return
        }

        let url = URL(string: "\(serverUrl)/\(versionId)/index.html")!
        let session = URLSession(configuration: URLSessionConfiguration.default, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: url) {(data, _, _) in
            guard let data = data else { return }
            DispatchQueue.main.async {
                self.webView.load(data, mimeType: "text/html", characterEncodingName: "uft8", baseURL: url)
            }
        }
        task.resume()
    }

    func refreshNavBar() {
        var actionsAvailable = [MiniAppNavigationAction]()
        if webView.canGoBack || navBarVisibility == .always {
            actionsAvailable.append(.back)
        }
        if webView.canGoForward || navBarVisibility == .always {
            actionsAvailable.append(.forward)
        }
        navigationDelegate?.miniAppNavigation(canUse: actionsAvailable)
        if actionsAvailable.count == 0 && navBarVisibility != .never {
            webViewBottomConstraintStandalone?.isActive = navBarVisibility == .auto
            webViewBottomConstraintWithNavBar?.isActive = navBarVisibility == .always
            navBar?.removeFromSuperview()
        } else {
            if let nav = navBar {
                let navDelegate = navigationDelegate as? UIView
                if navDelegate == nil || navDelegate != nav {
                    nav.miniAppNavigation(canUse: actionsAvailable)
                }

                if navBarVisibility != .never {
                    addSubview(nav)
                    nav.translatesAutoresizingMaskIntoConstraints = false
                    webViewBottomConstraintStandalone?.isActive = false || isNavBarCustom
                    webViewBottomConstraintWithNavBar?.isActive = true && !isNavBarCustom
                    nav.layoutAttachBottom()
                    nav.layoutAttachLeading()
                    nav.layoutAttachTrailing()
                }
            } else {
                webViewBottomConstraintWithNavBar?.isActive = false
                webViewBottomConstraintStandalone?.isActive = true
            }
        }
    }

    deinit {
        webView.configuration.userContentController.removeMessageHandler()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let requestUrl = navigationAction.request.url {
            validateScheme(requestURL: requestUrl, decisionHandler: decisionHandler)
        } else {
            decisionHandler(.cancel)
        }
    }

    func validateScheme(requestURL: URL, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let schemeType = MiniAppSupportedSchemes(rawValue: requestURL.scheme!)
        switch schemeType {
        case .tel:
            UIApplication.shared.open(requestURL, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
        default:
            decisionHandler(.allow)
        }
    }
}

extension RealMiniAppView: MiniAppDisplayProtocol {
    public func getMiniAppView() -> UIView {
        return self
    }
}

extension RealMiniAppView: MiniAppCallbackProtocol {
    func didReceiveScriptMessageResponse(messageId: String, response: String) {
        self.webView.evaluateJavaScript(Constants.javascriptSuccessCallback + "('\(messageId)'," + "'\(response)')")
    }

    func didReceiveScriptMessageError(messageId: String, errorMessage: String) {
        self.webView.evaluateJavaScript(Constants.javascriptErrorCallback + "('\(messageId)'," + "'\(errorMessage)')")
    }
}

extension RealMiniAppView: MiniAppNavigationBarDelegate {
    func miniAppNavigationBar(didTriggerAction action: MiniAppNavigationAction) -> Bool {
        let canDo: Bool
        switch action {
        case .back:
            canDo = self.webView.canGoBack
            self.webView.goBack()
        case .forward:
            canDo = self.webView.canGoForward
            self.webView.goForward()
        }
        return canDo
    }
}

extension RealMiniAppView: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshNavBar()
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        var disposition: URLSession.AuthChallengeDisposition = .performDefaultHandling
        var credential: URLCredential?

        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            disposition = URLSession.AuthChallengeDisposition.useCredential
            credential = URLCredential(trust: challenge.protectionSpace.serverTrust!)
        } else {
            if challenge.previousFailureCount > 0 {
                disposition = .cancelAuthenticationChallenge
            } else {
                credential = session.configuration.urlCredentialStorage?.defaultCredential(for: challenge.protectionSpace)
                if credential != nil {
                    disposition = .useCredential
                }
            }
        }
        completionHandler(disposition, credential)
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            return completionHandler(.useCredential, nil)
        }
        let exceptions = SecTrustCopyExceptions(serverTrust)
        SecTrustSetExceptions(serverTrust, exceptions)
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

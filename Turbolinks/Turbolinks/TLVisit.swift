import WebKit

protocol TLVisitDelegate: class {
    func visitWillIssueRequest(visit: TLVisit)
    func visitDidFinishRequest(visit: TLVisit)
    func visit(visit: TLVisit, didCompleteWithResponse response: String)
    func visitDidCompleteWebViewLoad(visit: TLVisit)
    func visitDidStart(visit: TLVisit)
    func visitDidFinish(visit: TLVisit)
}

class TLVisit: NSObject {
    var visitable: TLVisitable
    var request: NSURLRequest
    weak var delegate: TLVisitDelegate?
    
    enum State: String {
        case Initialized = "Initialized"
        case Started = "Started"
        case Completed = "Completed"
        case Canceled = "Canceled"
    }
    
    var requestState: State = .Initialized
    var navigationState: State = .Started
    var finished: Bool = false
    
    init(visitable: TLVisitable, request: NSURLRequest) {
        self.visitable = visitable
        self.request = request
    }
    
    func cancel() {
        cancelRequest()
        cancelNavigation()
        finish()
    }

    func finish() {
        if !finished {
            println("\(self) finish()")
            self.finished = true
            completeRequest()
            completeNavigation()
            delegate?.visitDidFinish(self)
        }
    }
    
    func startRequest() {
        if requestState == .Initialized {
            println("\(self) startRequest()")
            self.requestState = .Started
            delegate?.visitDidStart(self)
            delegate?.visitWillIssueRequest(self)
            issueRequest()
        }
    }
    
    func completeRequest() {
        if requestState == .Started {
            println("\(self) completeRequest()")
            self.requestState = .Completed
            delegate?.visitDidFinishRequest(self)
        }
    }
    
    func cancelRequest() {
        if requestState == .Started {
            println("\(self) cancelRequest()")
            self.requestState = .Canceled
            abortRequest()
            delegate?.visitDidFinishRequest(self)
            finish()
        }
    }
    
    func completeNavigation() {
        if navigationState == .Started {
            println("\(self) completeNavigation()")
            self.navigationState = .Completed
            navigationLock.unlock()
        }
    }
    
    func cancelNavigation() {
        if navigationState == .Started {
            println("\(self) cancelNavigation()")
            self.navigationState = .Canceled
            cancelRequest()
            finish()
        }
    }
    
    private func issueRequest() {}
    private func abortRequest() {}
    
    private lazy var navigationLock: TLLock = {
        return TLLock(queue: dispatch_get_main_queue())
    }()
    
    private func afterNavigationCompletion(callback: () -> ()) {
        navigationLock.afterUnlock(callback)
    }
}

class TLWebViewVisit: TLVisit, WKNavigationDelegate {
    var webView: WKWebView
    
    init(visitable: TLVisitable, request: NSURLRequest, webView: WKWebView) {
        self.webView = webView
        super.init(visitable: visitable, request: request)
    }
    
    override private func issueRequest() {
        webView.navigationDelegate = self
        webView.loadRequest(request)
    }
    
    func webView(webView: WKWebView, didFinishNavigation navigation: WKNavigation!) {
        webView.navigationDelegate = nil
        delegate?.visitDidCompleteWebViewLoad(self)
        finish()
    }
}

class TLTurbolinksVisit: TLVisit {
    private var sessionTask: NSURLSessionTask?
    
    override private func issueRequest() {
        if sessionTask == nil {
            let session = NSURLSession.sharedSession()
            self.sessionTask = session.dataTaskWithRequest(request) { (data, response, error) in
                if let httpResponse = response as? NSHTTPURLResponse {
                    self.handleResponse(httpResponse, data: data)
                }

                dispatch_async(dispatch_get_main_queue()) {
                    self.completeRequest()
                }
            }
            
            sessionTask?.resume()
        }
    }
    
    override private func abortRequest() {
        sessionTask?.cancel()
        self.sessionTask = nil
    }
    
    private func handleResponse(httpResponse: NSHTTPURLResponse, data: NSData) {
        if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
            if let response = NSString(data: data, encoding: NSUTF8StringEncoding) as? String {
                self.afterNavigationCompletion() {
                    self.delegate?.visit(self, didCompleteWithResponse: response)
                }
            }
        }
    }
}

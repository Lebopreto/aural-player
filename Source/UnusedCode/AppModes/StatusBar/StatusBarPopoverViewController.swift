///*
// View controller for the popover that displays a brief information message when a track is added to or removed from the Favorites list
// */
//import Cocoa
//
//// TODO: Can this be a general info popup ? "Tracks are being added ... (progress)" ?
//class StatusBarPopoverViewController: NSViewController, NSPopoverDelegate, MessageSubscriber {
//
//    var statusItem: NSStatusItem!
//
//    // The actual popover that is shown
//    private var popover: NSPopover!
//
//    // Popover positioning parameters
//    private let positioningRect = NSZeroRect
//
//    override var nibName: String? {return "StatusBarPopover"}
//
//    private var globalMouseClickMonitor: GlobalMouseClickMonitor!
//
//    private var gestureHandler: GestureHandler?
//
//    // Factory method
//    static func create() -> StatusBarPopoverViewController {
//        
//        let controller = StatusBarPopoverViewController()
//
//        let popover = NSPopover()
//        popover.behavior = .transient
//        popover.contentViewController = controller
//        popover.delegate = controller
//
//        controller.popover = popover
//
//        return controller
//    }
//
//    override func viewDidLoad() {
//
//        globalMouseClickMonitor = GlobalMouseClickMonitor([.leftMouseDown, .rightMouseDown], {(event: NSEvent!) -> Void in
//
//            // If window is non-nil, it means it's the popover window (first time after launching)
//            if event.window == nil {
//                self.close()
//            }
//        })
//
//        SyncMessenger.subscribe(messageTypes: [.appResignedActiveNotification], subscriber: self)
//
//        NSApp.unhide(self)
//    }
//
//    override func viewDidAppear() {
//
//        // Need to put this code here (and not in viewDidLoad()) because self.view.window is nil there
//        if (gestureHandler == nil) {
//
//            gestureHandler = GestureHandler(self.view.window!)
//            NSEvent.addLocalMonitorForEvents(matching: [.swipe, .scrollWheel], handler: {(event: NSEvent!) -> NSEvent in
//                self.gestureHandler!.handle(event)
//                return event;
//            });
//        }
//    }
//
//    @objc func statusBarButtonAction(_ sender: AnyObject) {
//        toggle(statusItem.button!, NSRectEdge.minY)
//    }
//
//    func toggle(_ relativeToView: NSView, _ preferredEdge: NSRectEdge) {
//
//        if (popover.isShown) {
//            close()
//        } else {
//            show(relativeToView, preferredEdge)
//        }
//    }
//
//    func show() {
//
//        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
//        if let btn = statusItem.button {
//
//            btn.image = NSImage(named: "AppIcon-StatusBar")
//            btn.action = #selector(self.statusBarButtonAction(_:))
//            btn.target = self
//        }
//
//        show(statusItem.button!, NSRectEdge.minY)
//    }
//
//    // Shows the popover
//    private func show(_ relativeToView: NSView, _ preferredEdge: NSRectEdge) {
//
//        if (!popover.isShown) {
//            popover.show(relativeTo: positioningRect, of: relativeToView, preferredEdge: preferredEdge)
//        }
//    }
//
//    // Closes the popover
//    func close() {
//
//        if (popover.isShown) {
//            popover.performClose(self)
//        }
//    }
//
//    func dismiss() {
//
//        close()
//        NSStatusBar.system.removeStatusItem(statusItem)
//    }
//
//    @IBAction func regularModeAction(_ sender: AnyObject) {
//
//        globalMouseClickMonitor.stop()
//
//        SyncMessenger.publishActionMessage(AppModeActionMessage(.regularAppMode))
//    }
//
//    @IBAction func quitAction(_ sender: AnyObject) {
//        NSApp.terminate(self)
//    }
//
//    private func appInactive() {
//        close()
//    }
//
//    func popoverDidShow(_ notification: Notification) {
//
//        NSApp.activate(ignoringOtherApps: true)
//        globalMouseClickMonitor.start()
//    }
//
//    func popoverDidClose(_ notification: Notification) {
//        globalMouseClickMonitor.stop()
//    }
//
//    var subscriberId: String {
//        return self.className
//    }
//
//    // MARK: Message handlers
//
//    // Consume synchronous notification messages
//    func consumeNotification(_ notification: NotificationMessage) {
//
//        switch notification.messageType {
//
//        case .appResignedActiveNotification:
//
//            appInactive()
//
//        default: return
//
//        }
//    }
//
//    // Process synchronous request messages
//    func processRequest(_ request: RequestMessage) -> ResponseMessage {
//
//        // This class does not process any requests
//        return EmptyResponse.instance
//    }
//}
//
//fileprivate class GlobalMouseClickMonitor {
//
//    private var monitor: Any?
//    private let mask: NSEvent.EventTypeMask
//    private let handler: (NSEvent?) -> Void
//
//    public init(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent?) -> Void) {
//        self.mask = mask
//        self.handler = handler
//    }
//
//    deinit {
//        stop()
//    }
//
//    public func start() {
//
//        if (monitor == nil) {
//            monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
//        }
//    }
//
//    public func stop() {
//
//        if monitor != nil {
//            NSEvent.removeMonitor(monitor!)
//            monitor = nil
//        }
//    }
//}

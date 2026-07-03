#if canImport(UIKit) || canImport(AppKit)
import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

/// Supported destinations for sharing an exported video.
public enum SocialShareTarget: String, Codable, Sendable, CaseIterable {
    case youTube
    case tikTok
    case instagram
    case twitter
    case facebook
    case saveToFiles
    case AirDrop
    case custom
}

/// Presents platform-native sharing services for exported videos.
public final class SocialShareService: Sendable {
    /// Shares a video URL using the current platform's sharing UI.
    public static func share(videoURL: URL, target: SocialShareTarget) async throws {
        #if canImport(UIKit)
        try await shareWithUIKit(videoURL: videoURL, target: target)
        #elseif canImport(AppKit)
        try await shareWithAppKit(videoURL: videoURL, target: target)
        #endif
    }

    /// Returns the currently advertised share targets.
    public static func availableTargets() -> [SocialShareTarget] {
        SocialShareTarget.allCases
    }

    #if canImport(UIKit)
    @MainActor
    private static func shareWithUIKit(videoURL: URL, target: SocialShareTarget) async throws {
        guard let presenter = topViewController() else {
            throw SocialShareServiceError.presentationUnavailable
        }

        let activityViewController = UIActivityViewController(activityItems: [videoURL], applicationActivities: nil)
        activityViewController.excludedActivityTypes = excludedActivityTypes(for: target)

        if let popoverPresentationController = activityViewController.popoverPresentationController {
            popoverPresentationController.sourceView = presenter.view
            popoverPresentationController.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0,
                height: 0
            )
            popoverPresentationController.permittedArrowDirections = []
        }

        presenter.present(activityViewController, animated: true)
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)

        guard let rootViewController = windows.first(where: \.isKeyWindow)?.rootViewController
            ?? windows.first?.rootViewController else {
            return nil
        }

        return visibleViewController(from: rootViewController)
    }

    @MainActor
    private static func visibleViewController(from viewController: UIViewController) -> UIViewController {
        if let presentedViewController = viewController.presentedViewController {
            return visibleViewController(from: presentedViewController)
        }

        if let navigationController = viewController as? UINavigationController,
           let navVisibleVC = navigationController.visibleViewController {
            return visibleViewController(from: navVisibleVC)
        }

        if let tabBarController = viewController as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return visibleViewController(from: selectedViewController)
        }

        return viewController
    }

    private static func excludedActivityTypes(for target: SocialShareTarget) -> [UIActivity.ActivityType]? {
        switch target {
        case .AirDrop:
            return nil
        case .saveToFiles:
            return nil
        case .youTube, .tikTok, .instagram, .twitter, .facebook, .custom:
            return nil
        }
    }
    #endif

    #if canImport(AppKit)
    @MainActor
    private static func shareWithAppKit(videoURL: URL, target: SocialShareTarget) async throws {
        let items: [Any] = [videoURL]

        if let service = sharingService(for: target) {
            guard service.canPerform(withItems: items) else {
                throw SocialShareServiceError.noSharingServiceAvailable
            }

            service.perform(withItems: items)
            return
        }

        guard let view = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView else {
            throw SocialShareServiceError.presentationUnavailable
        }

        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    @MainActor
    private static func sharingService(for target: SocialShareTarget) -> NSSharingService? {
        switch target {
        case .AirDrop:
            return NSSharingService(named: .sendViaAirDrop)
        case .youTube, .tikTok, .instagram, .twitter, .facebook, .saveToFiles, .custom:
            return nil
        }
    }
    #endif
}

private enum SocialShareServiceError: Error, Sendable {
    case presentationUnavailable
    case noSharingServiceAvailable
}
#endif

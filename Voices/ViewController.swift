import UIKit

final class ViewController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let library = VoiceLibraryViewController()
        library.tabBarItem = UITabBarItem(title: "我的声音", image: UIImage(systemName: "person.crop.circle"), tag: 0)
        let live = LiveVoiceViewController()
        live.tabBarItem = UITabBarItem(title: "实时变声", image: UIImage(systemName: "waveform"), tag: 1)
        let reader = ReaderViewController()
        reader.tabBarItem = UITabBarItem(title: "文字朗读", image: UIImage(systemName: "book"), tag: 2)
        viewControllers = [library, live, reader]
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = StudioTheme.background
        appearance.shadowColor = StudioTheme.border
        for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            item.normal.iconColor = StudioTheme.secondary
            item.normal.titleTextAttributes = [.foregroundColor: StudioTheme.secondary]
            item.selected.iconColor = StudioTheme.accent
            item.selected.titleTextAttributes = [.foregroundColor: StudioTheme.accent]
        }
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = StudioTheme.accent
    }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
}


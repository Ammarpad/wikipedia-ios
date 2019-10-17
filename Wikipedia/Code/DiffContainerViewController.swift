
import UIKit

struct StubRevisionModel {
    let revisionId: Int
    let summary: String
    let username: String
    let timestamp: Date
}

class DiffContainerViewController: ViewController {
    
    private var containerViewModel: DiffContainerViewModel
    private var headerExtendedView: DiffHeaderExtendedView?
    private var headerTitleView: DiffHeaderTitleView?
    private var diffListViewController: DiffListViewController?
    private let diffController: DiffController
    
    private let type: DiffContainerViewModel.DiffType
    
    //TONITODO: delete
    @objc static func stubCompareContainerViewController(theme: Theme) -> DiffContainerViewController {
        let revisionModel1 = StubRevisionModel(revisionId: 123, summary: "Summary 1", username: "fancypants", timestamp: Date(timeInterval: -(60*60*24*3), since: Date()))
        let revisionModel2 = StubRevisionModel(revisionId: 234, summary: "Summary 2", username: "funtimez2019", timestamp: Date(timeInterval: -(60*60*24*2), since: Date()))
        let stubCompareVC = DiffContainerViewController(type: .compare(articleTitle: "Dog", numberOfIntermediateRevisions: 1, numberOfIntermediateUsers: 1), fromModel: revisionModel1, toModel: revisionModel2, theme: theme, diffController: DiffController())
        return stubCompareVC
    }
    
    @objc static func stubSingleContainerViewController(theme: Theme) -> DiffContainerViewController {
        let revisionModel1 = StubRevisionModel(revisionId: 123, summary: "Summary 1", username: "fancypants", timestamp: Date(timeInterval: -(60*60*24*3), since: Date()))
        let revisionModel2 = StubRevisionModel(revisionId: 234, summary: "Summary 2", username: "funtimez2019", timestamp: Date(timeInterval: -(60*60*24*2), since: Date()))
        let stubSingleVC = DiffContainerViewController(type: .single(byteDifference: -6), fromModel: revisionModel1, toModel: revisionModel2, theme: theme, diffController: DiffController())
        return stubSingleVC
    }
    
    init(type: DiffContainerViewModel.DiffType, fromModel: StubRevisionModel, toModel: StubRevisionModel, theme: Theme, diffController: DiffController) {
        
        self.type = type
        self.diffController = diffController
        
        self.containerViewModel = DiffContainerViewModel(type: type, fromModel: fromModel, toModel: toModel, listViewModel: nil, theme: theme)
        
        super.init()
        
        self.theme = theme
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationController?.isNavigationBarHidden = true
        setupHeaderViewIfNeeded()
        setupDiffListViewControllerIfNeeded()
        apply(theme: theme)
        
        diffController.fetchDiff(theme: theme, traitCollection: traitCollection, type: type) { [weak self] (result) in

            guard let self = self else {
                return
            }

            switch result {
            case .success(let listViewModel):

                DispatchQueue.main.async {
                    self.diffListViewController?.dataSource = listViewModel
                    self.view.setNeedsLayout()
                    self.view.layoutIfNeeded()
                    self.diffListViewController?.updateScrollViewInsets()
                }
                
            case .failure(let error):
                print(error)
                //tonitodo: error handling
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if let scrollView = diffListViewController?.scrollView {
            configureExtendedViewSquishing(scrollView: scrollView)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.isNavigationBarHidden = false
    }
    
    override func apply(theme: Theme) {
        
        guard isViewLoaded else {
            return
        }
        
        super.apply(theme: theme)
        
        view.backgroundColor = theme.colors.paperBackground
        
        headerTitleView?.apply(theme: theme)
        headerExtendedView?.apply(theme: theme)
        diffListViewController?.apply(theme: theme)
    }
}

private extension DiffContainerViewController {
    
    func configureExtendedViewSquishing(scrollView: UIScrollView) {
        guard let headerTitleView = headerTitleView,
        let headerExtendedView = headerExtendedView else {
            return
        }
        
        let beginSquishYOffset = headerTitleView.frame.height
        let scrollYOffset = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        headerExtendedView.configureHeight(beginSquishYOffset: beginSquishYOffset, scrollYOffset: scrollYOffset)
    }
    
    func setupHeaderViewIfNeeded() {
        if self.headerTitleView == nil {
            let headerTitleView = DiffHeaderTitleView(frame: .zero)
            headerTitleView.translatesAutoresizingMaskIntoConstraints = false
            
            navigationBar.isUnderBarViewHidingEnabled = true
            navigationBar.allowsUnderbarHitsFallThrough = true
            navigationBar.addUnderNavigationBarView(headerTitleView)
            navigationBar.underBarViewPercentHiddenForShowingTitle = 0.6
            navigationBar.isShadowBelowUnderBarView = true
            
            self.headerTitleView = headerTitleView
        }
        
        if self.headerExtendedView == nil {
            let headerExtendedView = DiffHeaderExtendedView(frame: .zero)
            headerExtendedView.translatesAutoresizingMaskIntoConstraints = false
            
            navigationBar.allowsUnderbarHitsFallThrough = true
            navigationBar.allowsExtendedHitsFallThrough = true
            navigationBar.addExtendedNavigationBarView(headerExtendedView)
            
            self.headerExtendedView = headerExtendedView
        }
        
        navigationBar.isBarHidingEnabled = false
        useNavigationBarVisibleHeightForScrollViewInsets = true
        
        switch containerViewModel.headerViewModel.headerType {
        case .compare(_, let navBarTitle):
            navigationBar.title = navBarTitle
        default:
            break
        }
        
        headerTitleView?.update(containerViewModel.headerViewModel.title)
        headerExtendedView?.update(containerViewModel.headerViewModel)
        navigationBar.isExtendedViewHidingEnabled = containerViewModel.headerViewModel.isExtendedViewHidingEnabled
    }
    
    func setupDiffListViewControllerIfNeeded() {
        if diffListViewController == nil {
            let diffListViewController = DiffListViewController(theme: theme, delegate: self)
            wmf_add(childController: diffListViewController, andConstrainToEdgesOfContainerView: view, belowSubview: navigationBar)
            self.diffListViewController = diffListViewController
        }
    }
}

extension DiffContainerViewController: DiffListDelegate {
    func diffListScrollViewDidScroll(_ scrollView: UIScrollView) {
        self.scrollViewDidScroll(scrollView)
        
        configureExtendedViewSquishing(scrollView: scrollView)
    }
}

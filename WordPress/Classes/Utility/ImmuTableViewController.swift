import UIKit
import RxSwift
import WordPressShared

typealias ImmuTableRowControllerGenerator = ImmuTableRow -> UIViewController

protocol ImmuTablePresenter: class {
    func push(controllerGenerator: ImmuTableRowControllerGenerator) -> ImmuTableAction
    func present(controllerGenerator: ImmuTableRowControllerGenerator) -> ImmuTableAction
}

extension ImmuTablePresenter where Self: UIViewController {
    func push(controllerGenerator: ImmuTableRowControllerGenerator) -> ImmuTableAction {
        return {
            [unowned self] in
            let controller = controllerGenerator($0)
            self.navigationController?.pushViewController(controller, animated: true)
        }
    }

    func present(controllerGenerator: ImmuTableRowControllerGenerator) -> ImmuTableAction {
        return {
            [unowned self] in
            let controller = controllerGenerator($0)
            self.presentViewController(controller, animated: true, completion: nil)
        }
    }
}

extension ImmuTablePresenter {
    func prompt<T: UIViewController where T: Confirmable>(controllerGenerator: ImmuTableRow -> T) -> ImmuTableAction {
        return present({
            let controller = controllerGenerator($0)
            return PromptViewController(controller)
        })
    }
}

protocol ImmuTableController {
    var title: String { get }
    var immuTableRows: [ImmuTableRow.Type] { get }
    var noticeMessage: Observable<String?> { get }
    func tableViewModelWithPresenter(presenter: ImmuTablePresenter) -> Observable<ImmuTable>
}

/// Generic view controller to present ImmuTable-based tables
///
/// Instead of subclassing the view controller, this is designed to be used from
/// a "controller" class that handles all the logic, and updates the view
/// controller, like you would update a view.
final class ImmuTableViewController: UITableViewController, ImmuTablePresenter {
    private lazy var handler: ImmuTableViewHandler = {
        return ImmuTableViewHandler(takeOver: self)
    }()

    private var visibleSubject = PublishSubject<Bool>()

    private var noticeAnimator: NoticeAnimator!

    let controller: ImmuTableController

    private let bag = DisposeBag()

    // MARK: - Table View Controller

    init(controller: ImmuTableController) {
        self.controller = controller
        super.init(style: .Grouped)
        title = controller.title
        registerRows(controller.immuTableRows)
        controller.tableViewModelWithPresenter(self)
            .observeOn(MainScheduler.instance)
            .subscribeNext({ [weak self] in
                self?.handler.viewModel = $0
                })
            .addDisposableTo(bag)
        controller.noticeMessage
            .observeOn(MainScheduler.instance)
            .subscribeNext({ [weak self] in
                self?.noticeMessage = $0
                })
            .addDisposableTo(bag)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        noticeAnimator = NoticeAnimator(target: view)

        WPStyleGuide.resetReadableMarginsForTableView(tableView)
        WPStyleGuide.configureColorsForView(view, andTableView: tableView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        noticeAnimator.layout()
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        visibleSubject.on(.Next(true))
    }

    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        visibleSubject.on(.Next(false))
    }

    // MARK: - Inputs

    /// Registers custom rows
    /// - seealso: ImmuTable.registerRows(_:tableView)
    func registerRows(rows: [ImmuTableRow.Type]) {
        ImmuTable.registerRows(rows, tableView: tableView)
    }

    var noticeMessage: String? = nil {
        didSet {
            noticeAnimator.animateMessage(noticeMessage)
        }
    }

    // MARK: - Outputs

    /// Emits a value when the view controller appears or disappears
    var visible: Observable<Bool> {
        return visibleSubject
    }
}

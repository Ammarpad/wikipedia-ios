
import Foundation

enum DiffError: Error {
    case generateUrlFailure
    case missingDiffResponseFailure
    case missingUrlResponseFailure
    case fetchRevisionConstructTitleFailure
    case unrecognizedHardcodedIdsForIntermediateCounts
    
    var localizedDescription: String {
        return CommonStrings.genericErrorDescription
    }
}

//eventually used to power "Moved [down/up] n lines / Moved [down/up] n sections" text in diff
enum MoveDistance {
    case line(amount: Int)
    case section(amount: Int, name: String)
}

class DiffController {
    
    enum RevisionDirection {
        case next
        case previous
    }
    
    let diffFetcher: DiffFetcher
    let pageHistoryFetcher: PageHistoryFetcher?
    let globalUserInfoFetcher: GlobalUserInfoFetcher
    let diffThanker: DiffThanker
    let articleTitle: String
    let siteURL: URL
    lazy var semanticContentAttribute: UISemanticContentAttribute = {
        let language = siteURL.wmf_language
        return MWLanguageInfo.semanticContentAttribute(forWMFLanguage: language)
    }()
    let type: DiffContainerViewModel.DiffType
    private weak var revisionRetrievingDelegate: DiffRevisionRetrieving?

    init(siteURL: URL, articleTitle: String, diffFetcher: DiffFetcher = DiffFetcher(), pageHistoryFetcher: PageHistoryFetcher?, globalUserInfoFetcher: GlobalUserInfoFetcher = GlobalUserInfoFetcher(), diffThanker: DiffThanker = DiffThanker(), revisionRetrievingDelegate: DiffRevisionRetrieving?, type: DiffContainerViewModel.DiffType) {
        self.diffFetcher = diffFetcher
        self.pageHistoryFetcher = pageHistoryFetcher
        self.globalUserInfoFetcher = globalUserInfoFetcher
        self.diffThanker = diffThanker
        self.articleTitle = articleTitle
        self.siteURL = siteURL
        self.revisionRetrievingDelegate = revisionRetrievingDelegate
        self.type = type
    }
    
    func fetchEditCount(guiUser: String, siteURL: URL, completion: @escaping ((Result<Int, Error>) -> Void)) {
        globalUserInfoFetcher.fetchEditCount(guiUser: guiUser, siteURL: siteURL, completion: completion)
    }

    func fetchIntermediateCounts(for pageTitle: String, pageURL: URL, from fromRevisionID: Int , to toRevisionID: Int, completion: @escaping (Result<EditCountsGroupedByType, Error>) -> Void) {
        pageHistoryFetcher?.fetchEditCounts(.edits, .editors, for: pageTitle, pageURL: pageURL, from: fromRevisionID, to: toRevisionID, completion: completion)
    }
    
    func thankRevisionAuthor(toRevisionId: Int, completion: @escaping ((Result<DiffThankerResult, Error>) -> Void)) {
        diffThanker.thank(siteURL: siteURL, rev: toRevisionId, completion: completion)
    }
    
    func fetchRevision(sourceRevision: WMFPageHistoryRevision, direction: RevisionDirection, completion: @escaping ((Result<WMFPageHistoryRevision, Error>) -> Void)) {
        
        if let revisionRetrievingDelegate = revisionRetrievingDelegate {
            
            //optimization - first try to grab a revision we might already have in memory from the revisionRetrievingDelegate
            switch direction {
            case .next:
                if let nextRevision = revisionRetrievingDelegate.retrieveNextRevision(with: sourceRevision) {
                    completion(.success(nextRevision))
                    return
                }
            case .previous:
                if let previousRevision = revisionRetrievingDelegate.retrievePreviousRevision(with: sourceRevision) {
                    completion(.success(previousRevision))
                    return
                }
            }
        }
        
        //failing that try fetching revision from API
        guard let articleTitle = (articleTitle as NSString).wmf_normalizedPageTitle() else {
            completion(.failure(DiffError.fetchRevisionConstructTitleFailure))
            return
        }

        let direction: DiffFetcher.SingleRevisionRequestDirection = direction == .previous ? .older : .newer
        
        diffFetcher.fetchSingleRevisionInfo(siteURL, sourceRevision: sourceRevision, title: articleTitle, direction: direction, completion: completion)
    }
    
    func fetchDiff(fromRevisionId: Int, toRevisionId: Int, theme: Theme, traitCollection: UITraitCollection, completion: @escaping ((Result<[DiffListGroupViewModel], Error>) -> Void)) {
        
        diffFetcher.fetchDiff(fromRevisionId: fromRevisionId, toRevisionId: toRevisionId, siteURL: siteURL) { [weak self] (result) in

            guard let self = self else { return }

            switch result {
            case .success(var diffResponse):

                let groupedMoveIndexes = self.groupedIndexesOfMoveItems(from: diffResponse)
                self.hardCodeSectionInfo(into: &diffResponse, toRevisionID: toRevisionId)
                self.populateDeletedMovedSectionTitlesAndLineNumbers(into: &diffResponse)
                let moveDistances = self.moveDistanceOfMoveItems(from: diffResponse)
                switch self.type {
                case .single:
                    let response: [DiffListGroupViewModel] = self.viewModelsForSingle(from: diffResponse, theme: theme, traitCollection: traitCollection, type: self.type, groupedMoveIndexes: groupedMoveIndexes, moveDistances: moveDistances)

                    completion(.success(response))
                case .compare:
                    let response: [DiffListGroupViewModel] = self.viewModelsForCompare(from: diffResponse, theme: theme, traitCollection: traitCollection, type: self.type, groupedMoveIndexes: groupedMoveIndexes, moveDistances: moveDistances)
                    completion(.success(response))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func groupedIndexesOfMoveItems(from response: DiffResponse) -> [String: Int] {
        let movedItems = response.diff.filter { $0.type == .moveSource || $0.type == .moveDestination }
        
        var indexCounter = 0
        var result: [String: Int] = [:]
        
        for item in movedItems {
            
            if let id = item.moveInfo?.id,
                let linkId = item.moveInfo?.linkId {

                if result[id] == nil {
                    if let existingIndex = result[linkId] {
                        result[id] = existingIndex
                    } else {
                        result[id] = indexCounter
                        indexCounter += 1
                    }
                }
            }
        }
        
        return result
    }
    
    private func moveDistanceOfMoveItems(from response: DiffResponse) -> [String: MoveDistance] {
        let movedItems = response.diff.filter { $0.type == .moveSource || $0.type == .moveDestination }
        
        guard let sectionInfoArray = response.sectionInfo,
            !sectionInfoArray.isEmpty else {
                return [:]
        }
        
        var correspondingMoveItems: [String: DiffItem] = [:]
        for item in movedItems {
            if let linkId = item.moveInfo?.linkId {
                correspondingMoveItems[linkId] = item
            }
        }
        
        var result: [String: MoveDistance] = [:]
        for item in movedItems {
            if let id = item.moveInfo?.id,
                let linkId = item.moveInfo?.linkId,
                let correspondingItem = correspondingMoveItems[id] {
                
                if let sectionInfoIndex = item.sectionInfoIndex,
                    let correspondingSectionInfoIndex = correspondingItem.sectionInfoIndex,
                    let sectionInfo = sectionInfoArray[safeIndex: sectionInfoIndex],
                    let correspondingSectionInfo = sectionInfoArray[safeIndex: correspondingSectionInfoIndex] {
                    
                    let numSectionsTraversed = abs(correspondingSectionInfo.location - sectionInfo.location)
                    if numSectionsTraversed > 0 {
                        
                        let sectionMoveDistance = MoveDistance.section(amount: numSectionsTraversed, name: correspondingSectionInfo.title)
                        
                        if result[id] == nil && result[linkId] == nil {
                            result[id] = sectionMoveDistance
                            result[linkId] = sectionMoveDistance
                        }
                        
                        continue
                    }
                }
                
                if let lineNumber = item.lineNumber,
                    let correspondingLineNumber = correspondingItem.lineNumber {
                    
                    let lineNumbersTraversed = abs(lineNumber - correspondingLineNumber)
                    if lineNumbersTraversed > 0 {
                        
                        let lineNumberMoveDistance = MoveDistance.line(amount: lineNumbersTraversed)
                        result[id] = lineNumberMoveDistance
                        result[linkId] = lineNumberMoveDistance
                    }
                }
            }
        }
        
        return result
    }
    
    private func hardCodeSectionInfo(into response: inout DiffResponse, toRevisionID: Int) {
        if toRevisionID == 399777 {
            response.sectionInfo = [
                SectionInfo(title: "==Taxonomy==", location: 1),
                SectionInfo(title: "==Biology==", location: 2),
                SectionInfo(title: "===Senses===", location: 3)
//                SectionInfo(title: "====Vision====", location: 4),
//                SectionInfo(title: "===='''Hearing'''====", location: 5),
//                SectionInfo(title: "====Smell====", location: 6),
//                SectionInfo(title: "===Physical characteristics===", location: 7),
//                SectionInfo(title: "====Coat====", location: 8),
//                SectionInfo(title: "===Types and breeds===", location: 9),
//                SectionInfo(title: "== See also ==", location: 10),
//                SectionInfo(title: "==See also (as well)==", location: 11),
//                SectionInfo(title: "==References==", location: 12),
//                SectionInfo(title: "==Bibliography==", location: 13),
//                SectionInfo(title: "==Further reading==", location: 14),
//                SectionInfo(title: "== External links ==", location: 15),
            ]
            
            var newItems: [DiffItem] = []
            for (diffIndex, var item) in response.diff.enumerated() {
                switch diffIndex {
                case 0, 1, 4, 5: item.sectionInfoIndex = 0
                case 6, 7, 8, 9, 10: item.sectionInfoIndex = 1
                case 11: item.sectionInfoIndex = 2
                default:
                    break
                }
                
                newItems.append(item)
            }
            
            response.diff = newItems
        } else if toRevisionID == 392751 {
            //only intro (before any sections) changed on this one so not hardcoding any section info
        }
    }
    
    private func populateDeletedMovedSectionTitlesAndLineNumbers(into response: inout DiffResponse) {
        
        //We have some unknown sections and line numbers from the endpoint (deleted lines and moved paragraph sources, since they have no current place in the document). Fuzzying the logic here - propogating previous section infos and line numbers forward.
        
        var lastSectionInfoIndex: Int?
        var lastLineNumber: Int?
        
        var newItems: [DiffItem] = []
        for var item in response.diff {
            
            if let sectionInfoIndex = item.sectionInfoIndex {
                lastSectionInfoIndex = sectionInfoIndex
            } else {
                item.sectionInfoIndex = lastSectionInfoIndex
            }
            
            if let lineNumber = item.lineNumber {
                lastLineNumber = lineNumber
            } else {
                item.lineNumber = lastLineNumber
            }
            
            newItems.append(item)
        }
        
        response.diff = newItems
        
        //tonitodo: finish better logic, popualte section infos only if surrounded by items with the same section infos
        //test: if a section heading is deleted or moved, how does this handle?
        /*
         
         var lastSectionInfo: Int?
         var missingSectionTitleItems: [DiffItem] = []
         
         var newItems: [DiffItem] = []
         for var item in response.diff {
             
             if let sectionInfoIndex = item.sectionInfoIndex {
                 
                 if let lastSectionInfo = lastSectionInfo,
                     !missingSectionTitleItems.isEmpty,
                     sectionInfoIndex == lastSectionInfo {
                     //populate missing section title items & clean out
                     
                     for var item in missingSectionTitleItems {
                         item.sectionInfoIndex = lastSectionInfo
                     }
                     
                     missingSectionTitleItems.removeAll()
                 }
                    
                 
                 lastSectionInfo = sectionInfoIndex
             } else {
                 if lastSectionInfo != nil {
                     //start gathering items with missing section titles
                     missingSectionTitleItems.append(item)
                 }
             }
             
             newItems.append(item)
         }
         
         response.diff = newItems
         */
    }
    
    private func viewModelsForSingle(from response: DiffResponse, theme: Theme, traitCollection: UITraitCollection, type: DiffContainerViewModel.DiffType, groupedMoveIndexes: [String: Int], moveDistances: [String: MoveDistance]) -> [DiffListGroupViewModel] {
        
        var result: [DiffListGroupViewModel] = []
        
        var sectionItems: [DiffItem] = []
        var lastItem: DiffItem?

        let packageUpSectionItemsIfNeeded = {
            
            if sectionItems.count > 0 {
                //package contexts up into change view model, append to result
                
                let changeType: DiffListChangeType = .singleRevison
                
                let changeViewModel = DiffListChangeViewModel(type: changeType, diffItems: sectionItems, theme: theme, width: 0, traitCollection: traitCollection, groupedMoveIndexes: groupedMoveIndexes, moveDistances: moveDistances, sectionInfo: response.sectionInfo, semanticContentAttribute: self.semanticContentAttribute)
                result.append(changeViewModel)
                sectionItems.removeAll()
            }
            
        }
        
        for item in response.diff {

            
            if item.type == .context {
                
                continue
                
            } else {
                
                if item.sectionInfoIndex != lastItem?.sectionInfoIndex {
                    packageUpSectionItemsIfNeeded()
                }
                
                sectionItems.append(item)
            }
            
            lastItem = item
            
            continue
        }
        
        packageUpSectionItemsIfNeeded()
        
        return result
    }
        
    private func viewModelsForCompare(from response: DiffResponse, theme: Theme, traitCollection: UITraitCollection, type: DiffContainerViewModel.DiffType, groupedMoveIndexes: [String: Int], moveDistances: [String: MoveDistance]) -> [DiffListGroupViewModel] {
        
        var result: [DiffListGroupViewModel] = []
        
        var contextItems: [DiffItem] = []
        var changeItems: [DiffItem] = []
        var lastItem: DiffItem?
        
        let packageUpContextItemsIfNeeded = {
            
            if contextItems.count > 0 {
                //package contexts up into context view model, append to result
                let contextViewModel = DiffListContextViewModel(diffItems: contextItems, isExpanded: false, theme: theme, width: 0, traitCollection: traitCollection, semanticContentAttribute: self.semanticContentAttribute)
                result.append(contextViewModel)
                contextItems.removeAll()
            }
        }
        
        let packageUpChangeItemsIfNeeded = {
            
            if changeItems.count > 0 {
                //package contexts up into change view model, append to result
                
                let changeType: DiffListChangeType
                switch type {
                case .compare:
                    changeType = .compareRevision
                default:
                    changeType = .singleRevison
                }
                
                let changeViewModel = DiffListChangeViewModel(type: changeType, diffItems: changeItems, theme: theme, width: 0, traitCollection: traitCollection, groupedMoveIndexes: groupedMoveIndexes, moveDistances: moveDistances, sectionInfo: response.sectionInfo, semanticContentAttribute: self.semanticContentAttribute)
                result.append(changeViewModel)
                changeItems.removeAll()
            }
            
        }
        
        for item in response.diff {
            
            if let lastItemLineNumber = lastItem?.lineNumber,
                let currentItemLineNumber = item.lineNumber {
                let delta = currentItemLineNumber - lastItemLineNumber
                if delta > 1 {
                    
                    packageUpContextItemsIfNeeded()
                    packageUpChangeItemsIfNeeded()
                    
                    //insert unedited lines view model
                    let uneditedViewModel = DiffListUneditedViewModel(numberOfUneditedLines: delta, theme: theme, width: 0, traitCollection: traitCollection)
                    result.append(uneditedViewModel)
                }
            }
            
            if item.type == .context {
                
                packageUpChangeItemsIfNeeded()
                
                contextItems.append(item)
                
            } else {
                
                packageUpContextItemsIfNeeded()
                
                changeItems.append(item)
            }
            
            lastItem = item
            
            continue
        }
        
        packageUpContextItemsIfNeeded()
        packageUpChangeItemsIfNeeded()
        
        return result
    }
}

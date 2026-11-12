import Foundation
import XuejiCore

extension XuejiError {
    var localizedMessage: String {
        switch self {
        case .memberNotFound: return L("error.memberNotFound")
        case .memberInactive: return L("error.memberInactive")
        case .trackNotFound: return L("error.trackNotFound")
        case .itemNotFound: return L("error.itemNotFound")
        case .reviewNotFound: return L("error.reviewNotFound")
        case .emptyText: return L("error.emptyText")
        case .notPermitted: return L("error.notPermitted")
        case .agentRequiresHumanOwner: return L("error.agentRequiresHumanOwner")
        case .sourceRequiresValidURL: return L("error.sourceRequiresValidURL")
        case .itemNotApproved: return L("error.itemNotApproved")
        case .invalidApprovalState: return L("error.invalidApprovalState")
        case .notAResearchRequest: return L("error.notAResearchRequest")
        case .requestNotAssignedToAgent: return L("error.requestNotAssignedToAgent")
        case .requestAlreadyClaimed: return L("error.requestAlreadyClaimed")
        case .requestAlreadyCompleted: return L("error.requestAlreadyCompleted")
        case .leaseNotHeld: return L("error.leaseNotHeld")
        case .leaseExpired: return L("error.leaseExpired")
        case .reviewerCannotReviewOwnWork: return L("error.reviewerCannotReviewOwnWork")
        case .notTheReviewer: return L("error.notTheReviewer")
        case .reviewAlreadyResolved: return L("error.reviewAlreadyResolved")
        case .milestoneNotFound: return L("error.milestoneNotFound")
        case .typeNotFound: return L("error.typeNotFound")
        case .fieldNotFound: return L("error.fieldNotFound")
        case .invalidFieldKey: return L("error.invalidFieldKey")
        case .duplicateFieldKey: return L("error.duplicateFieldKey")
        case .invalidFieldValue: return L("error.invalidFieldValue")
        case .invalidFieldDefinition: return L("error.invalidFieldDefinition")
        case .requiredFieldMissing: return L("error.requiredFieldMissing")
        case .unrecognizedImport: return L("error.unrecognizedImport")
        case .unreadableImport: return L("error.unreadableImport")
        case .importIsStatements: return L("error.importIsStatements")
        case .importIsSourceTriage: return L("error.importIsSourceTriage")
        }
    }
}

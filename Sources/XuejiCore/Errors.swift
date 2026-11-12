import Foundation

public enum XuejiError: Error, Equatable, Sendable {
    case memberNotFound
    case memberInactive
    case trackNotFound
    case itemNotFound
    case reviewNotFound
    case emptyText
    case notPermitted
    case agentRequiresHumanOwner
    case sourceRequiresValidURL
    case itemNotApproved
    case invalidApprovalState
    case notAResearchRequest
    case requestNotAssignedToAgent
    case requestAlreadyClaimed
    case requestAlreadyCompleted
    case leaseNotHeld
    case leaseExpired
    case reviewerCannotReviewOwnWork
    case notTheReviewer
    case reviewAlreadyResolved
    case milestoneNotFound
    case typeNotFound
    case fieldNotFound
    case invalidFieldKey
    case duplicateFieldKey
    case invalidFieldValue
    case invalidFieldDefinition
    case requiredFieldMissing
    case unrecognizedImport
    case unreadableImport
    /// The PDF is a who-said-what-and-when table, but a source triage table was expected.
    case importIsStatements
    /// The PDF is a source triage table, but a who-said-what-and-when table was expected.
    case importIsSourceTriage
}

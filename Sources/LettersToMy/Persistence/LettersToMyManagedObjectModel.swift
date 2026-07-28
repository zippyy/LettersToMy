import CoreData
import Foundation

// The model is built in code so the repository remains XcodeGen-friendly while the
// schema is still changing quickly. Its entity and property names are stable and
// become the CloudKit record contract used by the native and web clients.
//
// Versioning strategy:
//   - versionIdentifiers = ["LettersToMyCoreDataV1"] is the initial schema.
//   - Future versions add new identifiers (e.g. "LettersToMyCoreDataV2") while
//     keeping all prior identifiers. Core Data lightweight migration handles
//     additive changes (new entities, new optional attributes) automatically.
//   - Renames, required-attribute additions, or relationship cardinality changes
//     require an explicit mapping model.
//   - Never ship a version that removes entities or attributes that have been
//     deployed to CloudKit without a migration window.
//
// UUID indexes:
//   Fetch indexes on stable UUID attributes speed up lookups by letter ID,
//   child ID, branch ID, and member ID — the common query patterns used by
//   the collaboration and delivery pipelines.
//
// Delete rules:
//   - Letter → Attachment: cascade (deleting a letter removes its attachments).
//   - Partition → child entities: nullify (deleting a share partition must
//     never cascade-delete the data it organizes). The partition exists to
//     group records for sharing; removing a share leaves the records intact.
//   - Delivery → DeliveryAttachment: cascade.
//   - All other relationships: nullify by default.
enum LettersToMyManagedObjectModel {
    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.versionIdentifiers = ["LettersToMyCoreDataV1"]

        let child = entity("ChildProfile", ChildProfile.self)
        child.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: zeroUUID),
            attribute("name", .stringAttributeType, defaultValue: ""),
            attribute("birthDate", .dateAttributeType, optional: true),
            attribute("createdAt", .dateAttributeType, defaultValue: epoch),
            attribute("updatedAt", .dateAttributeType, defaultValue: epoch)
        ]

        let letter = entity("Letter", Letter.self)
        letter.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: zeroUUID),
            attribute("childID", .UUIDAttributeType, optional: true),
            attribute("branchID", .UUIDAttributeType, optional: true),
            attribute("folderID", .UUIDAttributeType, optional: true),
            attribute("authorMemberID", .UUIDAttributeType, optional: true),
            attribute("title", .stringAttributeType, defaultValue: ""),
            attribute("body", .stringAttributeType, defaultValue: ""),
            attribute("authorName", .stringAttributeType, defaultValue: ""),
            attribute("createdAt", .dateAttributeType, defaultValue: epoch),
            attribute("updatedAt", .dateAttributeType, defaultValue: epoch),
            attribute("sealedAt", .dateAttributeType, optional: true),
            attribute("isFavorite", .booleanAttributeType, defaultValue: false),
            attribute("unlockRuleRawValue", .stringAttributeType, defaultValue: "specificDate"),
            attribute("unlockDate", .dateAttributeType, optional: true),
            attribute("unlockAgeYearsValue", .integer16AttributeType, optional: true),
            attribute("lifeEventName", .stringAttributeType, defaultValue: ""),
            attribute("manuallyReleasedAt", .dateAttributeType, optional: true)
        ]

        let attachment = entity("LetterAttachment", LetterAttachment.self)
        attachment.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: zeroUUID),
            attribute("letterID", .UUIDAttributeType, defaultValue: zeroUUID),
            attribute("fileName", .stringAttributeType, defaultValue: "Attachment"),
            attribute("contentTypeIdentifier", .stringAttributeType, defaultValue: "public.data"),
            attribute("createdAt", .dateAttributeType, defaultValue: epoch),
            attribute("kindRawValue", .stringAttributeType, defaultValue: "file"),
            attribute("data", .binaryDataAttributeType, optional: true, externalStorage: true)
        ]

        let branch = entity("FamilyBranchRecord", FamilyBranchRecord.self)
        branch.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: zeroUUID),
            attribute("name", .stringAttributeType, defaultValue: ""),
            attribute("kindRawValue", .stringAttributeType, defaultValue: "custom"),
            attribute("parentBranchID", .UUIDAttributeType, optional: true),
            attribute("createdAt", .dateAttributeType, defaultValue: epoch),
            attribute("updatedAt", .dateAttributeType, defaultValue: epoch)
        ]

        let folder = entity("ArchiveFolderRecord", ArchiveFolderRecord.self)
        folder.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: zeroUUID),
            attribute("branchID", .UUIDAttributeType, defaultValue: zeroUUID),
            attribute("parentFolderID", .UUIDAttributeType, optional: true),
            attribute("name", .stringAttributeType, defaultValue: ""),
            attribute("createdAt", .dateAttributeType, defaultValue: epoch),
            attribute("updatedAt", .dateAttributeType, defaultValue: epoch)
        ]

        let member = entity("ArchiveMemberRecord", ArchiveMemberRecord.self)
        member.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: zeroUUID),
            attribute("displayName", .stringAttributeType, defaultValue: ""),
            attribute("relationship", .stringAttributeType, defaultValue: ""),
            attribute("roleRawValue", .stringAttributeType, defaultValue: "viewer"),
            attribute("statusRawValue", .stringAttributeType, defaultValue: "invited"),
            attribute("scopeData", .binaryDataAttributeType, optional: true),
            attribute("grantedPermissionsData", .binaryDataAttributeType, optional: true),
            attribute("deniedPermissionsData", .binaryDataAttributeType, optional: true),
            attribute("canInviteOthers", .booleanAttributeType, defaultValue: false),
            attribute("cloudKitParticipantRecordName", .stringAttributeType, optional: true),
            attribute("createdAt", .dateAttributeType, defaultValue: epoch),
            attribute("updatedAt", .dateAttributeType, defaultValue: epoch)
        ]

        let invitation = entity("CollaborationInvitationRecord", CollaborationInvitationRecord.self)
        invitation.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: zeroUUID),
            attribute("inviteeDisplayName", .stringAttributeType, defaultValue: ""),
            attribute("inviteeAddress", .stringAttributeType, defaultValue: ""),
            attribute("relationship", .stringAttributeType, defaultValue: ""),
            attribute("roleRawValue", .stringAttributeType, defaultValue: "contributor"),
            attribute("scopeData", .binaryDataAttributeType, optional: true),
            attribute("statusRawValue", .stringAttributeType, defaultValue: "pending"),
            attribute("createdAt", .dateAttributeType, defaultValue: epoch),
            attribute("expiresAt", .dateAttributeType, optional: true),
            attribute("intendedRecipientID", .UUIDAttributeType, optional: true),
            attribute("canInviteOthers", .booleanAttributeType, defaultValue: false),
            attribute("intendedMemberID", .UUIDAttributeType, optional: true),
            attribute("ckShareRecordName", .stringAttributeType, optional: true),
            attribute("memberActivationData", .binaryDataAttributeType, optional: true)
        ]

        let partition = entity("SharePartitionRecord", SharePartitionRecord.self)
        partition.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: zeroUUID),
            attribute("kindRawValue", .stringAttributeType, defaultValue: "archiveAdministration"),
            attribute("scopeID", .UUIDAttributeType, optional: true),
            attribute("displayName", .stringAttributeType, defaultValue: "Family Archive"),
            attribute("createdAt", .dateAttributeType, defaultValue: epoch),
            attribute("updatedAt", .dateAttributeType, defaultValue: epoch),
            attribute("memberActivationData", .binaryDataAttributeType, optional: true)
        ]

        let letterAttachments = toMany("attachments", destination: attachment, deleteRule: .cascadeDeleteRule)
        let attachmentLetter = toOne("letter", destination: letter, deleteRule: .nullifyDeleteRule)
        inverse(letterAttachments, attachmentLetter)
        letter.properties.append(letterAttachments)
        attachment.properties.append(attachmentLetter)

        attachPartitionRelationship(
            source: child,
            sourceName: "partition",
            destination: partition,
            destinationName: "children"
        )
        attachPartitionRelationship(
            source: letter,
            sourceName: "partition",
            destination: partition,
            destinationName: "letters"
        )
        attachPartitionRelationship(
            source: branch,
            sourceName: "partition",
            destination: partition,
            destinationName: "branches"
        )
        attachPartitionRelationship(
            source: folder,
            sourceName: "partition",
            destination: partition,
            destinationName: "folders"
        )
        attachPartitionRelationship(
            source: member,
            sourceName: "partition",
            destination: partition,
            destinationName: "members"
        )
        attachPartitionRelationship(
            source: invitation,
            sourceName: "partition",
            destination: partition,
            destinationName: "invitations"
        )

        let backupRecord = entity("BackupRecordEntity", BackupRecordEntity.self)
        backupRecord.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: zeroUUID),
            attribute("destinationRawValue", .stringAttributeType, defaultValue: "localFile"),
            attribute("statusRawValue", .stringAttributeType, defaultValue: "completed"),
            attribute("createdAt", .dateAttributeType, defaultValue: epoch),
            attribute("completedAt", .dateAttributeType, optional: true),
            attribute("sizeBytes", .integer64AttributeType, defaultValue: Int64(0)),
            attribute("letterCount", .integer64AttributeType, defaultValue: Int64(0)),
            attribute("attachmentCount", .integer64AttributeType, defaultValue: Int64(0)),
            attribute("errorMessage", .stringAttributeType, optional: true),
            attribute("remoteIdentifier", .stringAttributeType, optional: true)
        ]

        let recoveryContact = entity("RecoveryContactEntity", RecoveryContactEntity.self)
        recoveryContact.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: zeroUUID),
            attribute("displayName", .stringAttributeType, defaultValue: ""),
            attribute("emailAddress", .stringAttributeType, defaultValue: ""),
            attribute("phoneNumber", .stringAttributeType, optional: true),
            attribute("relationship", .stringAttributeType, defaultValue: ""),
            attribute("recoveryKeyHash", .binaryDataAttributeType, optional: true),
            attribute("notes", .stringAttributeType, optional: true),
            attribute("createdAt", .dateAttributeType, defaultValue: epoch),
            attribute("updatedAt", .dateAttributeType, defaultValue: epoch)
        ]

        let deliveryAttachment = entity("DeliveryAttachmentEntity", DeliveryAttachmentEntity.self)
        deliveryAttachment.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: zeroUUID),
            attribute("fileName", .stringAttributeType, defaultValue: "Attachment"),
            attribute("contentTypeIdentifier", .stringAttributeType, defaultValue: "public.data"),
            attribute("kindRawValue", .stringAttributeType, defaultValue: "file"),
            attribute("data", .binaryDataAttributeType, optional: true, externalStorage: true)
        ]

        let delivery = entity("DeliveryRecordEntity", DeliveryRecordEntity.self)
        delivery.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: zeroUUID),
            attribute("recipientID", .UUIDAttributeType, defaultValue: zeroUUID),
            attribute("originalLetterID", .UUIDAttributeType, defaultValue: zeroUUID),
            attribute("title", .stringAttributeType, defaultValue: ""),
            attribute("body", .stringAttributeType, defaultValue: ""),
            attribute("authorName", .stringAttributeType, defaultValue: ""),
            attribute("deliveredAt", .dateAttributeType, defaultValue: epoch),
            attribute("readAt", .dateAttributeType, optional: true),
            attribute("replyBody", .stringAttributeType, optional: true),
            attribute("repliedAt", .dateAttributeType, optional: true),
            attribute("stateRawValue", .stringAttributeType, defaultValue: "delivered")
        ]

        let deliveryAttachments = toMany("deliveryAttachments", destination: deliveryAttachment, deleteRule: .cascadeDeleteRule)
        let attachmentDelivery = toOne("delivery", destination: delivery, deleteRule: .nullifyDeleteRule)
        inverse(deliveryAttachments, attachmentDelivery)
        delivery.properties.append(deliveryAttachments)
        deliveryAttachment.properties.append(attachmentDelivery)

        attachPartitionRelationship(
            source: delivery,
            sourceName: "partition",
            destination: partition,
            destinationName: "deliveries"
        )

        let entities = [child, letter, attachment, branch, folder, member, invitation, partition, backupRecord, recoveryContact, delivery, deliveryAttachment]
        model.entities = entities
        model.setEntities(entities, forConfigurationName: PersistenceController.privateConfigurationName)
        model.setEntities(entities, forConfigurationName: PersistenceController.sharedConfigurationName)

        // NSPersistentCloudKitContainer auto-creates indexes for id and
        // reference attributes (childID, recipientID, letterID, etc.).
        // Manual indexes duplicate these and crash at store load.
        // Do not add manual fetch indexes here — CloudKit handles them.

        // Runtime hardening: verify critical delete rules before deployment.
        validatePartitionDeleteRules(
            model: model,
            partition: partition
        )
        validateCascadeRules(
            model: model,
            letter: letter,
            delivery: delivery
        )

        return model
    }

    private static let epoch = Date(timeIntervalSince1970: 0)
    private static let zeroUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    private static func entity(_ name: String, _ managedClass: AnyClass) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = NSStringFromClass(managedClass)
        return entity
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool = false,
        defaultValue: Any? = nil,
        externalStorage: Bool = false
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        attribute.defaultValue = defaultValue
        attribute.allowsExternalBinaryDataStorage = externalStorage
        return attribute
    }

    private static func toOne(
        _ name: String,
        destination: NSEntityDescription,
        deleteRule: NSDeleteRule
    ) -> NSRelationshipDescription {
        let relationship = NSRelationshipDescription()
        relationship.name = name
        relationship.destinationEntity = destination
        relationship.minCount = 0
        relationship.maxCount = 1
        relationship.isOptional = true
        relationship.deleteRule = deleteRule
        return relationship
    }

    private static func toMany(
        _ name: String,
        destination: NSEntityDescription,
        deleteRule: NSDeleteRule
    ) -> NSRelationshipDescription {
        let relationship = NSRelationshipDescription()
        relationship.name = name
        relationship.destinationEntity = destination
        relationship.minCount = 0
        relationship.maxCount = 0
        relationship.isOptional = true
        relationship.isOrdered = false
        relationship.deleteRule = deleteRule
        return relationship
    }

    private static func inverse(
        _ first: NSRelationshipDescription,
        _ second: NSRelationshipDescription
    ) {
        first.inverseRelationship = second
        second.inverseRelationship = first
    }

    private static func attachPartitionRelationship(
        source: NSEntityDescription,
        sourceName: String,
        destination: NSEntityDescription,
        destinationName: String
    ) {
        let toPartition = toOne(sourceName, destination: destination, deleteRule: .nullifyDeleteRule)
        let fromPartition = toMany(destinationName, destination: source, deleteRule: .nullifyDeleteRule)
        inverse(toPartition, fromPartition)
        source.properties.append(toPartition)
        destination.properties.append(fromPartition)
    }

    /// Adds a Core Data fetch index on a single UUID attribute so that
    /// queries filtering by that attribute use an indexed scan instead of
    /// a full table scan. CloudKit does not use these indexes directly,
    /// but the local SQLite store benefits significantly.
    private static func addUUIDIndex(
        to entity: NSEntityDescription,
        attribute name: String
    ) {
        guard let property = entity.propertiesByName[name] as? NSAttributeDescription else {
            return
        }
        let element = NSFetchIndexElementDescription(
            property: property,
            collationType: .binary
        )
        let index = NSFetchIndexDescription(
            name: "\(entity.name!)_\(name)_idx",
            elements: [element]
        )
        // NSPersistentCloudKitContainer may auto-create an index for
        // the "id" attribute; avoid a duplicate-index crash.
        if entity.indexes.contains(where: { $0.name == index.name }) {
            return
        }
        entity.indexes.append(index)
    }

    /// Guards against accidental data loss: partition relationships must
    /// use nullify, never cascade. If a future edit regresses this, the
    /// assertion fires at app launch during development.
    private static func validatePartitionDeleteRules(
        model: NSManagedObjectModel,
        partition: NSEntityDescription
    ) {
        let relationships = [
            "children", "letters", "branches", "folders",
            "members", "invitations", "deliveries"
        ]
        for name in relationships {
            guard let rel = partition.relationshipsByName[name] else { continue }
            assert(
                rel.deleteRule == .nullifyDeleteRule,
                "Partition relationship '\(name)' must use nullify, not cascade. "
                + "Found: \(rel.deleteRule.rawValue)"
            )
        }
    }

    /// Guards the intentional cascade rules: letter→attachments and
    /// delivery→attachments must cascade so deleting a parent cleans up
    /// child records.
    private static func validateCascadeRules(
        model: NSManagedObjectModel,
        letter: NSEntityDescription,
        delivery: NSEntityDescription
    ) {
        if let letterAtt = letter.relationshipsByName["attachments"] {
            assert(
                letterAtt.deleteRule == .cascadeDeleteRule,
                "Letter→attachments must use cascade. Found: \(letterAtt.deleteRule.rawValue)"
            )
        }
        if let deliveryAtt = delivery.relationshipsByName["deliveryAttachments"] {
            assert(
                deliveryAtt.deleteRule == .cascadeDeleteRule,
                "Delivery→attachments must use cascade. Found: \(deliveryAtt.deleteRule.rawValue)"
            )
        }
    }
}

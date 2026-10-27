//
//  ShoppingList+CoreDataProperties.swift
//  
//
//  Created by Kaleb on 10/27/26.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias ShoppingListCoreDataPropertiesSet = NSSet

extension ShoppingList {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ShoppingList> {
        return NSFetchRequest<ShoppingList>(entityName: "ShoppingList")
    }

    @NSManaged nonisolated public var createdAt: Date?
    @NSManaged nonisolated public var id: UUID?
    @NSManaged nonisolated public var name: String?
    @NSManaged nonisolated public var sortOrder: Int16
    @NSManaged nonisolated public var household: Household?
    @NSManaged nonisolated public var items: NSSet?

}

// MARK: Generated accessors for items
extension ShoppingList {

    @objc(addItemsObject:)
    @NSManaged nonisolated public func addToItems(_ value: ShoppingItem)

    @objc(removeItemsObject:)
    @NSManaged nonisolated public func removeFromItems(_ value: ShoppingItem)

    @objc(addItems:)
    @NSManaged nonisolated public func addToItems(_ values: NSSet)

    @objc(removeItems:)
    @NSManaged nonisolated public func removeFromItems(_ values: NSSet)

}

extension ShoppingList : Identifiable {

}

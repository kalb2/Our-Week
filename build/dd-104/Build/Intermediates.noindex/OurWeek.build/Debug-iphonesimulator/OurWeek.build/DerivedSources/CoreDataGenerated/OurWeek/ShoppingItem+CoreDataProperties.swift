//
//  ShoppingItem+CoreDataProperties.swift
//  
//
//  Created by Kaleb on 10/27/26.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias ShoppingItemCoreDataPropertiesSet = NSSet

extension ShoppingItem {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ShoppingItem> {
        return NSFetchRequest<ShoppingItem>(entityName: "ShoppingItem")
    }

    @NSManaged nonisolated public var category: String?
    @NSManaged nonisolated public var id: UUID?
    @NSManaged nonisolated public var isChecked: Bool
    @NSManaged nonisolated public var name: String?
    @NSManaged nonisolated public var quantity: String?
    @NSManaged nonisolated public var list: ShoppingList?

}

extension ShoppingItem : Identifiable {

}

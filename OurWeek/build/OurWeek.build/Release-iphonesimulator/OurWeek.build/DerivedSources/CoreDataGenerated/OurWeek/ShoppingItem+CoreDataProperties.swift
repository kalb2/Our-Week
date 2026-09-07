//
//  ShoppingItem+CoreDataProperties.swift
//  
//
//  Created by Kaleb Jensen on 3/27/26.
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

    @NSManaged public var category: String?
    @NSManaged public var id: UUID?
    @NSManaged public var isChecked: Bool
    @NSManaged public var name: String?
    @NSManaged public var quantity: String?
    @NSManaged public var list: ShoppingList?

}

extension ShoppingItem : Identifiable {

}

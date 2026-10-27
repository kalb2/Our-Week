//
//  RecipeIngredient+CoreDataProperties.swift
//  
//
//  Created by Kaleb on 10/27/26.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias RecipeIngredientCoreDataPropertiesSet = NSSet

extension RecipeIngredient {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<RecipeIngredient> {
        return NSFetchRequest<RecipeIngredient>(entityName: "RecipeIngredient")
    }

    @NSManaged nonisolated public var amount: Double
    @NSManaged nonisolated public var id: UUID?
    @NSManaged nonisolated public var name: String?
    @NSManaged nonisolated public var notes: String?
    @NSManaged nonisolated public var sectionName: String?
    @NSManaged nonisolated public var sortOrder: Int16
    @NSManaged nonisolated public var unit: String?
    @NSManaged nonisolated public var recipe: Recipe?

}

extension RecipeIngredient : Identifiable {

}

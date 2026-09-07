//
//  RecipeIngredient+CoreDataProperties.swift
//  
//
//  Created by Kaleb Jensen on 3/27/26.
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

    @NSManaged public var amount: Double
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var notes: String?
    @NSManaged public var sectionName: String?
    @NSManaged public var sortOrder: Int16
    @NSManaged public var unit: String?
    @NSManaged public var recipe: Recipe?

}

extension RecipeIngredient : Identifiable {

}

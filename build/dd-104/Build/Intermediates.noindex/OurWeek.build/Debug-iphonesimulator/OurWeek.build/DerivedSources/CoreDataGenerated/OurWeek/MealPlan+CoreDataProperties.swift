//
//  MealPlan+CoreDataProperties.swift
//  
//
//  Created by Kaleb on 10/27/26.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias MealPlanCoreDataPropertiesSet = NSSet

extension MealPlan {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<MealPlan> {
        return NSFetchRequest<MealPlan>(entityName: "MealPlan")
    }

    @NSManaged nonisolated public var date: Date?
    @NSManaged nonisolated public var id: UUID?
    @NSManaged nonisolated public var ingredients: String?
    @NSManaged nonisolated public var mealType: String?
    @NSManaged nonisolated public var notes: String?
    @NSManaged nonisolated public var title: String?
    @NSManaged nonisolated public var household: Household?
    @NSManaged nonisolated public var recipe: Recipe?

}

extension MealPlan : Identifiable {

}

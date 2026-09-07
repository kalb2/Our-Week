//
//  MealPlan+CoreDataProperties.swift
//  
//
//  Created by Kaleb Jensen on 3/27/26.
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

    @NSManaged public var date: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var ingredients: String?
    @NSManaged public var mealType: String?
    @NSManaged public var notes: String?
    @NSManaged public var title: String?
    @NSManaged public var household: Household?
    @NSManaged public var recipe: Recipe?

}

extension MealPlan : Identifiable {

}

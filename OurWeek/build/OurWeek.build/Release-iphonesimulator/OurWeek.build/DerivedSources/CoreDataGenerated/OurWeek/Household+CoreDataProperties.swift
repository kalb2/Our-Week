//
//  Household+CoreDataProperties.swift
//  
//
//  Created by Kaleb Jensen on 3/27/26.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias HouseholdCoreDataPropertiesSet = NSSet

extension Household {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Household> {
        return NSFetchRequest<Household>(entityName: "Household")
    }

    @NSManaged public var createdAt: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var ownerName: String?
    @NSManaged public var events: NSSet?
    @NSManaged public var mealPlans: NSSet?
    @NSManaged public var recipes: NSSet?
    @NSManaged public var shoppingLists: NSSet?

}

// MARK: Generated accessors for events
extension Household {

    @objc(addEventsObject:)
    @NSManaged public func addToEvents(_ value: CalendarEvent)

    @objc(removeEventsObject:)
    @NSManaged public func removeFromEvents(_ value: CalendarEvent)

    @objc(addEvents:)
    @NSManaged public func addToEvents(_ values: NSSet)

    @objc(removeEvents:)
    @NSManaged public func removeFromEvents(_ values: NSSet)

}

// MARK: Generated accessors for mealPlans
extension Household {

    @objc(addMealPlansObject:)
    @NSManaged public func addToMealPlans(_ value: MealPlan)

    @objc(removeMealPlansObject:)
    @NSManaged public func removeFromMealPlans(_ value: MealPlan)

    @objc(addMealPlans:)
    @NSManaged public func addToMealPlans(_ values: NSSet)

    @objc(removeMealPlans:)
    @NSManaged public func removeFromMealPlans(_ values: NSSet)

}

// MARK: Generated accessors for recipes
extension Household {

    @objc(addRecipesObject:)
    @NSManaged public func addToRecipes(_ value: Recipe)

    @objc(removeRecipesObject:)
    @NSManaged public func removeFromRecipes(_ value: Recipe)

    @objc(addRecipes:)
    @NSManaged public func addToRecipes(_ values: NSSet)

    @objc(removeRecipes:)
    @NSManaged public func removeFromRecipes(_ values: NSSet)

}

// MARK: Generated accessors for shoppingLists
extension Household {

    @objc(addShoppingListsObject:)
    @NSManaged public func addToShoppingLists(_ value: ShoppingList)

    @objc(removeShoppingListsObject:)
    @NSManaged public func removeFromShoppingLists(_ value: ShoppingList)

    @objc(addShoppingLists:)
    @NSManaged public func addToShoppingLists(_ values: NSSet)

    @objc(removeShoppingLists:)
    @NSManaged public func removeFromShoppingLists(_ values: NSSet)

}

extension Household : Identifiable {

}

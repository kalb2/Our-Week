//
//  Household+CoreDataProperties.swift
//  
//
//  Created by Kaleb on 10/27/26.
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

    @NSManaged nonisolated public var createdAt: Date?
    @NSManaged nonisolated public var id: UUID?
    @NSManaged nonisolated public var name: String?
    @NSManaged nonisolated public var ownerName: String?
    @NSManaged nonisolated public var events: NSSet?
    @NSManaged nonisolated public var mealPlans: NSSet?
    @NSManaged nonisolated public var recipes: NSSet?
    @NSManaged nonisolated public var shoppingLists: NSSet?

}

// MARK: Generated accessors for events
extension Household {

    @objc(addEventsObject:)
    @NSManaged nonisolated public func addToEvents(_ value: CalendarEvent)

    @objc(removeEventsObject:)
    @NSManaged nonisolated public func removeFromEvents(_ value: CalendarEvent)

    @objc(addEvents:)
    @NSManaged nonisolated public func addToEvents(_ values: NSSet)

    @objc(removeEvents:)
    @NSManaged nonisolated public func removeFromEvents(_ values: NSSet)

}

// MARK: Generated accessors for mealPlans
extension Household {

    @objc(addMealPlansObject:)
    @NSManaged nonisolated public func addToMealPlans(_ value: MealPlan)

    @objc(removeMealPlansObject:)
    @NSManaged nonisolated public func removeFromMealPlans(_ value: MealPlan)

    @objc(addMealPlans:)
    @NSManaged nonisolated public func addToMealPlans(_ values: NSSet)

    @objc(removeMealPlans:)
    @NSManaged nonisolated public func removeFromMealPlans(_ values: NSSet)

}

// MARK: Generated accessors for recipes
extension Household {

    @objc(addRecipesObject:)
    @NSManaged nonisolated public func addToRecipes(_ value: Recipe)

    @objc(removeRecipesObject:)
    @NSManaged nonisolated public func removeFromRecipes(_ value: Recipe)

    @objc(addRecipes:)
    @NSManaged nonisolated public func addToRecipes(_ values: NSSet)

    @objc(removeRecipes:)
    @NSManaged nonisolated public func removeFromRecipes(_ values: NSSet)

}

// MARK: Generated accessors for shoppingLists
extension Household {

    @objc(addShoppingListsObject:)
    @NSManaged nonisolated public func addToShoppingLists(_ value: ShoppingList)

    @objc(removeShoppingListsObject:)
    @NSManaged nonisolated public func removeFromShoppingLists(_ value: ShoppingList)

    @objc(addShoppingLists:)
    @NSManaged nonisolated public func addToShoppingLists(_ values: NSSet)

    @objc(removeShoppingLists:)
    @NSManaged nonisolated public func removeFromShoppingLists(_ values: NSSet)

}

extension Household : Identifiable {

}

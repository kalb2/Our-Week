//
//  Recipe+CoreDataProperties.swift
//  
//
//  Created by Kaleb on 10/27/26.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias RecipeCoreDataPropertiesSet = NSSet

extension Recipe {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Recipe> {
        return NSFetchRequest<Recipe>(entityName: "Recipe")
    }

    @NSManaged nonisolated public var categories: String?
    @NSManaged nonisolated public var cookTime: Int16
    @NSManaged nonisolated public var createdAt: Date?
    @NSManaged nonisolated public var difficulty: String?
    @NSManaged nonisolated public var id: UUID?
    @NSManaged nonisolated public var imageData: Data?
    @NSManaged nonisolated public var ingredients: String?
    @NSManaged nonisolated public var instructions: String?
    @NSManaged nonisolated public var isFavorite: Bool
    @NSManaged nonisolated public var lastCookedDate: Date?
    @NSManaged nonisolated public var name: String?
    @NSManaged nonisolated public var notes: String?
    @NSManaged nonisolated public var prepTime: Int16
    @NSManaged nonisolated public var rating: Int16
    @NSManaged nonisolated public var recipeDescription: String?
    @NSManaged nonisolated public var servings: Int16
    @NSManaged nonisolated public var tags: String?
    @NSManaged nonisolated public var sourceDomain: String?
    @NSManaged nonisolated public var sourceURL: String?
    @NSManaged nonisolated public var timesCooked: Int16
    @NSManaged nonisolated public var updatedAt: Date?
    @NSManaged nonisolated public var household: Household?
    @NSManaged nonisolated public var mealPlans: NSSet?
    @NSManaged nonisolated public var recipeIngredients: NSSet?
    @NSManaged nonisolated public var recipeInstructions: NSSet?

}

// MARK: Generated accessors for mealPlans
extension Recipe {

    @objc(addMealPlansObject:)
    @NSManaged nonisolated public func addToMealPlans(_ value: MealPlan)

    @objc(removeMealPlansObject:)
    @NSManaged nonisolated public func removeFromMealPlans(_ value: MealPlan)

    @objc(addMealPlans:)
    @NSManaged nonisolated public func addToMealPlans(_ values: NSSet)

    @objc(removeMealPlans:)
    @NSManaged nonisolated public func removeFromMealPlans(_ values: NSSet)

}

// MARK: Generated accessors for recipeIngredients
extension Recipe {

    @objc(addRecipeIngredientsObject:)
    @NSManaged nonisolated public func addToRecipeIngredients(_ value: RecipeIngredient)

    @objc(removeRecipeIngredientsObject:)
    @NSManaged nonisolated public func removeFromRecipeIngredients(_ value: RecipeIngredient)

    @objc(addRecipeIngredients:)
    @NSManaged nonisolated public func addToRecipeIngredients(_ values: NSSet)

    @objc(removeRecipeIngredients:)
    @NSManaged nonisolated public func removeFromRecipeIngredients(_ values: NSSet)

}

// MARK: Generated accessors for recipeInstructions
extension Recipe {

    @objc(addRecipeInstructionsObject:)
    @NSManaged nonisolated public func addToRecipeInstructions(_ value: RecipeInstruction)

    @objc(removeRecipeInstructionsObject:)
    @NSManaged nonisolated public func removeFromRecipeInstructions(_ value: RecipeInstruction)

    @objc(addRecipeInstructions:)
    @NSManaged nonisolated public func addToRecipeInstructions(_ values: NSSet)

    @objc(removeRecipeInstructions:)
    @NSManaged nonisolated public func removeFromRecipeInstructions(_ values: NSSet)

}

extension Recipe : Identifiable {

}

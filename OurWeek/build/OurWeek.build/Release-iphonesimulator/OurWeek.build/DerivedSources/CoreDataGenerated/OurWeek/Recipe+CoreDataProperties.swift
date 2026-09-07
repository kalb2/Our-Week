//
//  Recipe+CoreDataProperties.swift
//  
//
//  Created by Kaleb Jensen on 3/27/26.
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

    @NSManaged public var categories: String?
    @NSManaged public var cookTime: Int16
    @NSManaged public var createdAt: Date?
    @NSManaged public var difficulty: String?
    @NSManaged public var id: UUID?
    @NSManaged public var imageData: Data?
    @NSManaged public var ingredients: String?
    @NSManaged public var instructions: String?
    @NSManaged public var isFavorite: Bool
    @NSManaged public var lastCookedDate: Date?
    @NSManaged public var name: String?
    @NSManaged public var notes: String?
    @NSManaged public var prepTime: Int16
    @NSManaged public var rating: Int16
    @NSManaged public var recipeDescription: String?
    @NSManaged public var servings: Int16
    @NSManaged public var tags: String?
    @NSManaged public var sourceDomain: String?
    @NSManaged public var sourceURL: String?
    @NSManaged public var timesCooked: Int16
    @NSManaged public var updatedAt: Date?
    @NSManaged public var household: Household?
    @NSManaged public var mealPlans: NSSet?
    @NSManaged public var recipeIngredients: NSSet?
    @NSManaged public var recipeInstructions: NSSet?

}

// MARK: Generated accessors for mealPlans
extension Recipe {

    @objc(addMealPlansObject:)
    @NSManaged public func addToMealPlans(_ value: MealPlan)

    @objc(removeMealPlansObject:)
    @NSManaged public func removeFromMealPlans(_ value: MealPlan)

    @objc(addMealPlans:)
    @NSManaged public func addToMealPlans(_ values: NSSet)

    @objc(removeMealPlans:)
    @NSManaged public func removeFromMealPlans(_ values: NSSet)

}

// MARK: Generated accessors for recipeIngredients
extension Recipe {

    @objc(addRecipeIngredientsObject:)
    @NSManaged public func addToRecipeIngredients(_ value: RecipeIngredient)

    @objc(removeRecipeIngredientsObject:)
    @NSManaged public func removeFromRecipeIngredients(_ value: RecipeIngredient)

    @objc(addRecipeIngredients:)
    @NSManaged public func addToRecipeIngredients(_ values: NSSet)

    @objc(removeRecipeIngredients:)
    @NSManaged public func removeFromRecipeIngredients(_ values: NSSet)

}

// MARK: Generated accessors for recipeInstructions
extension Recipe {

    @objc(addRecipeInstructionsObject:)
    @NSManaged public func addToRecipeInstructions(_ value: RecipeInstruction)

    @objc(removeRecipeInstructionsObject:)
    @NSManaged public func removeFromRecipeInstructions(_ value: RecipeInstruction)

    @objc(addRecipeInstructions:)
    @NSManaged public func addToRecipeInstructions(_ values: NSSet)

    @objc(removeRecipeInstructions:)
    @NSManaged public func removeFromRecipeInstructions(_ values: NSSet)

}

extension Recipe : Identifiable {

}

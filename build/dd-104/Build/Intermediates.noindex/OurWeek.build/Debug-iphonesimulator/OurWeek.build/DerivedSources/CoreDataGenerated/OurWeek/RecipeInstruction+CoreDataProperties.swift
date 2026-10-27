//
//  RecipeInstruction+CoreDataProperties.swift
//  
//
//  Created by Kaleb on 10/27/26.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias RecipeInstructionCoreDataPropertiesSet = NSSet

extension RecipeInstruction {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<RecipeInstruction> {
        return NSFetchRequest<RecipeInstruction>(entityName: "RecipeInstruction")
    }

    @NSManaged nonisolated public var id: UUID?
    @NSManaged nonisolated public var stepNumber: Int16
    @NSManaged nonisolated public var text: String?
    @NSManaged nonisolated public var timerSeconds: Int32
    @NSManaged nonisolated public var recipe: Recipe?

}

extension RecipeInstruction : Identifiable {

}

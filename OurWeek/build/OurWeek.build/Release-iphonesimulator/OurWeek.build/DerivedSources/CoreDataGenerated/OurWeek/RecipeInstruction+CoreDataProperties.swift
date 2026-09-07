//
//  RecipeInstruction+CoreDataProperties.swift
//  
//
//  Created by Kaleb Jensen on 3/27/26.
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

    @NSManaged public var id: UUID?
    @NSManaged public var stepNumber: Int16
    @NSManaged public var text: String?
    @NSManaged public var timerSeconds: Int32
    @NSManaged public var recipe: Recipe?

}

extension RecipeInstruction : Identifiable {

}

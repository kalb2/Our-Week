//
//  CalendarEvent+CoreDataProperties.swift
//  
//
//  Created by Kaleb Jensen on 3/27/26.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias CalendarEventCoreDataPropertiesSet = NSSet

extension CalendarEvent {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CalendarEvent> {
        return NSFetchRequest<CalendarEvent>(entityName: "CalendarEvent")
    }

    @NSManaged public var appleEventID: String?
    @NSManaged public var color: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var date: Date?
    @NSManaged public var endDate: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var isAllDay: Bool
    @NSManaged public var notes: String?
    @NSManaged public var title: String?
    @NSManaged public var household: Household?

}

extension CalendarEvent : Identifiable {

}

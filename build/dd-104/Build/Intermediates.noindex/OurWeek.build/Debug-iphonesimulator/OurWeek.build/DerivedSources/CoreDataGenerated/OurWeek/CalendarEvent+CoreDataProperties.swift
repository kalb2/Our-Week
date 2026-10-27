//
//  CalendarEvent+CoreDataProperties.swift
//  
//
//  Created by Kaleb on 10/27/26.
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

    @NSManaged nonisolated public var appleEventID: String?
    @NSManaged nonisolated public var color: String?
    @NSManaged nonisolated public var createdAt: Date?
    @NSManaged nonisolated public var date: Date?
    @NSManaged nonisolated public var endDate: Date?
    @NSManaged nonisolated public var id: UUID?
    @NSManaged nonisolated public var isAllDay: Bool
    @NSManaged nonisolated public var notes: String?
    @NSManaged nonisolated public var title: String?
    @NSManaged nonisolated public var household: Household?

}

extension CalendarEvent : Identifiable {

}

/*
@author: Gandhi Naidu Bokam
@Date: 24-09-2026
@ref: https://1218globaluk.eu.teamwork.com/app/tasks/36242290
*/
public class EventSubtypeSyncHandler {

    public static void handleTrigger(List<Event> events) {

        List<Event> eventsToUpdate = new List<Event>();

        for (Event e : events) {

            if (e.EventSubtype != null) {

                eventsToUpdate.add(new Event(
                    Id = e.Id,
                    Event_Subtype__c = e.EventSubtype
                ));
            }
        }

        if (!eventsToUpdate.isEmpty()) {
            update eventsToUpdate;
        }
    }
}
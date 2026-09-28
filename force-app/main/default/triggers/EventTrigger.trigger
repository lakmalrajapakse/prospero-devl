/*
@author: Gandhi Naidu Bokam
@Date: 24-09-2026
@ref: https://1218globaluk.eu.teamwork.com/app/tasks/36242290
*/
trigger EventTrigger on Event (after insert) {
    EventSubtypeSyncHandler.handleTrigger(Trigger.new);
}
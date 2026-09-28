/**
 * @description The batch responsible creating the most up the date Textkernel Taxonomy
 */
public with sharing class BH_MasterSkillBatch implements Database.Batchable<sObject> { 
     
    
    /**
     * @description The query locator of the batch
     * @param context The context  ID
     * @return the query locator thats gonna be used 
     */
    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            Select Id, TR1__Owner__c, TR1__Applicant__r.OwnerId FROM TR1__Application_V2__c WHERE TR1__Owner__c = null
        ]);
    }
     /**
     * @description The execute part of the batch
     * @param context The context ID
     * @param apps List of Application records
     */
    public void execute(Database.BatchableContext context, List<TR1__Application_V2__c> apps) {
        

    }
    
     /**
     * @description The finish part of the batch
     * @param context The context  ID 
     */
    public void finish(Database.BatchableContext context) {
        // Do nothing
    } 

}
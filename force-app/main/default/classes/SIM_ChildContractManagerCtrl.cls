/**
 * @description Controller for the childContractManager LWC.
 *              Manages creation and update of WFM Contracts for child accounts,
 *              linked back to a parent contract via Linked_Contract__c.
 * @author      Lakmal Rajapakse
 * @group       WFM Contracts
 * @last modified on  : 2026-06-30
**/
public with sharing class SIM_ChildContractManagerCtrl {

    /**
     * Loads the parent contract details, all descendant accounts of the contract's account
     * (children, grandchildren, and so on down the account hierarchy), and any existing
     * contracts already linked to this parent contract.
     */
    @AuraEnabled
    public static String getChildAccountData(Id contractId) {
        try {
            sirenum__ProActiveContract__c parentContract = [
                SELECT Id, Name, sirenum__Client__c, sirenum__Client__r.Name, Linked_Contract__c
                FROM sirenum__ProActiveContract__c
                WHERE Id = :contractId
                LIMIT 1
            ];

            List<Account> childAccounts = new List<Account>();
            if (parentContract.Linked_Contract__c == null) {
                childAccounts = getAllDescendantAccounts(parentContract.sirenum__Client__c);
            } 
                        
            childAccounts.sort(new AccountNameComparator());

            Set<Id> childAccountIds = new Set<Id>();
            for (Account acc : childAccounts) {
                childAccountIds.add(acc.Id);
            }

            Map<Id, sirenum__ProActiveContract__c> linkedByAccount = new Map<Id, sirenum__ProActiveContract__c>();
            if (!childAccountIds.isEmpty()) {
                for (sirenum__ProActiveContract__c lc : [
                    SELECT Id, Name, sirenum__Client__c
                    FROM sirenum__ProActiveContract__c
                    WHERE Linked_Contract__c = :contractId
                    AND sirenum__Client__c IN :childAccountIds
                ]) {
                    linkedByAccount.put(lc.sirenum__Client__c, lc);
                }
            }

            Map<String, Object> response = new Map<String, Object>{
                'contractId'       => parentContract.Id,
                'contractName'     => parentContract.Name,
                'parentAccountId'  => parentContract.sirenum__Client__c,
                'parentAccountName'=> parentContract.sirenum__Client__r.Name
            };

            List<Map<String, Object>> rows = new List<Map<String, Object>>();
            for (Account acc : childAccounts) {
                sirenum__ProActiveContract__c lc = linkedByAccount.get(acc.Id);
                rows.add(new Map<String, Object>{
                    'accountId'         => acc.Id,
                    'accountName'       => acc.Name,                    
                    'hasLinkedContract' => lc != null,
                    'linkedContractId'  => lc != null ? lc.Id   : null,
                    'linkedContractName'=> lc != null ? lc.Name : null
                });
            }
            response.put('childAccountRows', rows);

            return JSON.serialize(response);

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Creates or updates child contracts for the selected rows.
     * New contracts copy fieldset-defined fields from the parent contract.
     * Existing contracts only update Invoice Authoriser and Cost Centre.
     */
    @AuraEnabled
    public static String saveChildContracts(Id contractId, String selectedRowsJSON) {
        try {
            List<Object> selectedRows = (List<Object>) JSON.deserializeUntyped(selectedRowsJSON);
            if (selectedRows == null || selectedRows.isEmpty()) {
                throw new AuraHandledException('No rows provided.');
            }

            List<Schema.FieldSetMember> fsMembers = getFieldSetMembers();

            // Build dynamic SOQL to load parent with all fieldset fields
            Set<String> addedLower = new Set<String>{'id','name','sirenum__client__c'};
            String parentFields = 'Id, Name, sirenum__Client__c';
            for (Schema.FieldSetMember fsm : fsMembers) {
                if (!addedLower.contains(fsm.getFieldPath().toLowerCase())) {
                    parentFields += ', ' + fsm.getFieldPath();
                    addedLower.add(fsm.getFieldPath().toLowerCase());
                }
            }

            sirenum__ProActiveContract__c parentContract = Database.query(
                'SELECT ' + parentFields + ' FROM sirenum__ProActiveContract__c WHERE Id = :contractId LIMIT 1'
            );

            List<sirenum__ProActiveContract__c> toInsert = new List<sirenum__ProActiveContract__c>();

            for (Object item : selectedRows) {
                Map<String, Object> rowData = (Map<String, Object>) item;

                // Skip rows that already have a linked contract
                if (toId(rowData.get('linkedContractId')) != null) continue;

                Id accountId       = toId(rowData.get('accountId'));
                
                String contractName = String.valueOf(rowData.get('accountName')).left(80 - parentContract.Name.length() - 3) + ' - ' + parentContract.Name;                                    

                sirenum__ProActiveContract__c newContract = new sirenum__ProActiveContract__c(
                    sirenum__Client__c = accountId,
                    Linked_Contract__c = contractId,
                    Name               = contractName
                );
                for (Schema.FieldSetMember fsm : fsMembers) {
                    newContract.put(fsm.getFieldPath(), parentContract.get(fsm.getFieldPath()));
                }
                toInsert.add(newContract);
            }

            if (!toInsert.isEmpty()) insert toInsert;

            return JSON.serialize(new Map<String, Object>{
                'success'      => true,
                'insertedCount'=> toInsert.size()
            });

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Walks the Account hierarchy level by level starting from parentAccountId,
     * collecting every descendant account (children, grandchildren, etc).
     */
    private static List<Account> getAllDescendantAccounts(Id parentAccountId) {
        List<Account> descendants = new List<Account>();
        Set<Id> seenIds = new Set<Id>();
        Set<Id> currentLevelIds = new Set<Id>{ parentAccountId };

        while (!currentLevelIds.isEmpty()) {
            List<Account> level = [
                SELECT Id, Name
                FROM Account
                WHERE ParentId IN :currentLevelIds
            ];

            Set<Id> nextLevelIds = new Set<Id>();
            for (Account acc : level) {
                if (!seenIds.contains(acc.Id)) {
                    seenIds.add(acc.Id);
                    descendants.add(acc);
                    nextLevelIds.add(acc.Id);
                }
            }
            currentLevelIds = nextLevelIds;
        }

        return descendants;
    }

    private class AccountNameComparator implements Comparator<Account> {
        public Integer compare(Account a1, Account a2) {
            String name1 = a1.Name == null ? '' : a1.Name;
            String name2 = a2.Name == null ? '' : a2.Name;
            return name1.compareTo(name2);
        }
    }

    private static List<Schema.FieldSetMember> getFieldSetMembers() {
        Schema.FieldSet fs = Schema.SObjectType.sirenum__ProActiveContract__c
            .fieldSets.getMap().get('Contract_Clone_Fields');
        return fs != null ? fs.getFields() : new List<Schema.FieldSetMember>();
    }

    private static Id toId(Object val) {
        if (val == null) return null;
        String s = String.valueOf(val);
        return (String.isBlank(s) || s == 'null') ? null : (Id) s;
    }
}
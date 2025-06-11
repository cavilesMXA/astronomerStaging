global class AccountSalesActivityCount implements Schedulable, Database.Batchable<SObject> {

    private Set<String> allowedProfiles  = new Set<String>();
    private List<Sales_Activity_Count_Profiles__mdt> spl = new List<Sales_Activity_Count_Profiles__mdt>();


    global void execute(SchedulableContext sc) {
        Database.executeBatch(this, 1);
    }
    public AccountSalesActivityCount (){
        retrieveMetadata();
    }

    global Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([SELECT Id, of_Sales_Activities_Last_15_Days__c  FROM Account   ]);
    }

    public void retrieveMetadata(){

        List<Sales_Activity_Count_Profiles__mdt> spl = new List<Sales_Activity_Count_Profiles__mdt>();
        spl = [SELECT Id, DeveloperName,MasterLabel FROM Sales_Activity_Count_Profiles__mdt];
        for (Sales_Activity_Count_Profiles__mdt sp : spl) {
            allowedProfiles.add(sp.MasterLabel);
        }
    }

    global void execute(Database.BatchableContext context, List<Account> accounts) {
        try
        {
            Date start = System.today() - 15;
            Map<Id, List<Task>> accMap = new Map<Id, List<Task>>();
            for (Account s : accounts) {
                s.of_Sales_Activities_Last_15_Days__c = 0;          
            }
    
            List <Task> allTasks = [SELECT Account_ID_via_contact__c, Id, Is_Inbound__c, TaskSubtype, Type, CallDisposition, ActivityDate,WhatId FROM Task WHERE WhatId IN: accounts  AND ActivityDate >= :start and CreatedBy.Profile.Name in :allowedProfiles ORDER BY ActivityDate DESC];
    
            for (Task t : allTasks) {
    
                if(!accmap.containsKey(t.WhatId))
                {
                    accMap.put(t.WhatId, new List<Task>());
                    accMap.get(t.WhatId).add(t);
                }
                else 
                {
                    accMap.get(t.WhatId).add(t);
                }
            }
    
            for (Account acc : accounts) {
                if(accMap.get(acc.Id) != null)
                    acc.of_Sales_Activities_Last_15_Days__c = accMap.get(acc.Id)?.size();   
                else 
                     acc.of_Sales_Activities_Last_15_Days__c = 0;
                     
            }
           
    
            update accounts;

        }

        catch(Exception e){
            System.debug('error messaege : ' + e.getMessage());
            System.debug('error line: ' + e.getLineNumber());
        }
      
    }

    global void finish(Database.BatchableContext context) {
    }
}
@isTest
public with sharing class AccountSalesActivityCountTest  {
    @isTest
    static void testTaskQueryWithFilters() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Sales - AE' LIMIT 1];  

        User u = new User(
            Username = 'testuserastronomer' + DateTime.now().format('yyyyMMddHHmmss') + '@example.com',
            LastName = 'Test',
            Email = 'testuser@example.com',
            Alias = 'testu',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert u;

        Account acct = new Account(Name = 'Test Account');
        insert acct;

        Contact con = new Contact(FirstName = 'Test', LastName = 'Contact', AccountId = acct.Id);
        insert con;


        List<Task> tskList = new List<Task>();

        System.runAs(u) {

            for(Integer i = 0; i < 10; i++){
                Task t = new Task(
                    Subject = '[Outreach] tEST',
                    WhatId = acct.Id,
                    WhoId = con.Id,
                    OwnerId = u.Id,
                    Status = 'Completed',
                    ActivityDate = Date.today()-15,                          
                    TaskSubtype = 'Call',
                    Type = 'Call',
                    CallDisposition = 'Connected'
                );
                tskList.add(t);
    
    
            }
            insert tskList;

            }

        Task t = new Task(
                Subject = '[Outreach] tEST',
                WhatId = acct.Id,
                WhoId = con.Id,
                OwnerId = u.Id,
                Status = 'Completed',
                ActivityDate = Date.today()-15,                          
                TaskSubtype = 'Call',
                Type = 'Call',
                CallDisposition = 'Connected'
            );
        insert t;

        

        Test.startTest();
        Database.executeBatch(new AccountSalesActivityCount());

        Test.stopTest();

        Account accUpdt = [Select Id,of_Sales_Activities_Last_15_Days__c from Account Where Id =:acct.Id];
        System.assertEquals(10, accUpdt.of_Sales_Activities_Last_15_Days__c, 'Expecting 10 Tasks for this account');

    }


    @isTest
    static void testTaskQueryWithFilters_Bulk() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Sales - AE' LIMIT 1];  

        List<User> users = new List<User>();
        List<Account> accounts = new List<Account>();
        List<Contact> contacts = new List<Contact>();
        List<Task> allTasks = new List<Task>();

        for (Integer uIdx = 0; uIdx < 3; uIdx++) {
            users.add(new User(
                Username = 'testuserastronomer' + uIdx + DateTime.now().format('yyyyMMddHHmmss') + '@example.com',
                LastName = 'Test',
                Email = 'testuser' + uIdx + '@example.com',
                Alias = 'testu' + uIdx,
                TimeZoneSidKey = 'America/New_York',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                ProfileId = p.Id,
                LanguageLocaleKey = 'en_US'
            ));
        }
        insert users;

        for (Integer i = 0; i < 3; i++) {
            Account acct = new Account(Name = 'Test Account ' + i);
            accounts.add(acct);
        }
        insert accounts;

        for (Integer i = 0; i < accounts.size(); i++) {
            contacts.add(new Contact(
                FirstName = 'Test',
                LastName = 'Contact ' + i,
                AccountId = accounts[i].Id
            ));
        }
        insert contacts;

        for (Integer i = 0; i < accounts.size(); i++) {
            User u = users[i];
            Contact con = contacts[i];
            Account acct = accounts[i];

            System.runAs(u) {
                List<Task> tasks = new List<Task>();
                for (Integer j = 0; j < 10; j++) {
                    tasks.add(new Task(
                        Subject = '[Outreach] Test',
                        WhatId = acct.Id,
                        WhoId = con.Id,
                        OwnerId = u.Id,
                        Status = 'Completed',
                        ActivityDate = Date.today() - 15,
                        TaskSubtype = 'Call',
                        Type = 'Call',
                        CallDisposition = 'Connected' 
                    ));
                }
                insert tasks;
                allTasks.addAll(tasks);
            }
        }

        Test.startTest();
        Database.executeBatch(new AccountSalesActivityCount());
        Test.stopTest();

        for (Account acct : accounts) {
            Account result = [SELECT Id, of_Sales_Activities_Last_15_Days__c FROM Account WHERE Id = :acct.Id];
            System.assertEquals(10, result.of_Sales_Activities_Last_15_Days__c, 'Each account should have 10 tasks');
        }
    }
}

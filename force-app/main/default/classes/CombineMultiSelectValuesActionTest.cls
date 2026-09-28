@IsTest
private class CombineMultiSelectValuesActionTest {
    @IsTest
    static void testRemoveDuplicates() {
        CombineMultiSelectValuesAction.Request request = new CombineMultiSelectValuesAction.Request();
        request.values1 = new List<String>{'VNOC;Social Worker', 'Social Worker;3D Animator', 'Warehouse'};
        request.values2 = new List<String>{'Teaching', 'Teaching;Mathematics', 'Mathematics'};
        request.values3 = new List<String>{'3-4;4-8', '4-8;8-11', '3-4'};

        Test.startTest();
        List<CombineMultiSelectValuesAction.Response> responses = CombineMultiSelectValuesAction.removeDuplicates(new List<CombineMultiSelectValuesAction.Request>{request});
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals('3D Animator;Social Worker;VNOC;Warehouse', responses[0].result1);
        System.assertEquals('Mathematics;Teaching', responses[0].result2);
        System.assertEquals('3-4;4-8;8-11', responses[0].result3);
    }

    @IsTest
    static void testBlankAndNullValues() {
        CombineMultiSelectValuesAction.Request request = new CombineMultiSelectValuesAction.Request();
        request.values1 = new List<String>{'', null, 'VNOC;VNOC', 'Social Worker'};
        request.values2 = new List<String>{'', 'Teaching', 'Teaching'};
        request.values3 = null;

        Test.startTest();
        List<CombineMultiSelectValuesAction.Response> responses = CombineMultiSelectValuesAction.removeDuplicates(new List<CombineMultiSelectValuesAction.Request>{request});
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals('Social Worker;VNOC', responses[0].result1);
        System.assertEquals('Teaching', responses[0].result2);
        System.assertEquals('', responses[0].result3);
    }
}
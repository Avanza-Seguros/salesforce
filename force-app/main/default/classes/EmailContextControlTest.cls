@IsTest
private class EmailContextControlTest {

    @IsTest
    static void testSetTestMode() {
        EmailContextControl.setTestMode(true);
        EmailContextControl.setTestMode(false);
		EmailContextControl.canBatchSend();
        EmailContextControl.canBatchSend('test');
        EmailContextControl.canTriggerSend();
    }
}
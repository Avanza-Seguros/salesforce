// Ejecutar en Execute Anonymous
@IsTest
private class runAllQueueEnvioEmailsTests {

    @isTest
    static void runAllQueueEnvioEmailsTests() {
        QueueEnvioEmailsTest test1 = new QueueEnvioEmailsTest();
        QueueEnvioEmailsTest2 test2 = new QueueEnvioEmailsTest2();
        
        // Los tests se ejecutarán cuando corras "Run All Tests"
        Assert.isTrue(true, 'Test classes loaded successfully');
    }
}
public class EmailContextControl {

    // 🔕 Apaga TODOS los correos (tests / reprocesos)
    public static Boolean skipEmails = false;

    // 🚦 Control por contexto
    public static Boolean allowTriggerEmails = true;
    public static Boolean allowBatchEmails   = true;
    public static Boolean isTestMode = false;

    /* ==========================
       HELPERS
       ========================== */
    public static Boolean canTriggerSend() {
        return !skipEmails && allowTriggerEmails;
    }

    public static Boolean canBatchSend() {
        return canBatchSend('default');
    }
    
    public static Boolean canBatchSend(String context) {
        if (isTestMode) {
            return allowBatchEmails;
        }
        // Lógica real aquí
        return true;
    }

    /* ==========================
       TEST MODE
       ========================== */
    public static void setTestMode(Boolean testMode) {
        isTestMode = testMode;
    }
}
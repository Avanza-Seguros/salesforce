// TriggerControl.cls
public class TriggerControl {
    // Control para evitar recursión
    public static Boolean isExecuting = false;
    public static Boolean skipEmailTrigger = false;
    public static Set<Id> processedItems = new Set<Id>();
    
    // Verificar si ya procesamos este item en esta transacción
    public static Boolean isAlreadyProcessed(Id itemId) {
        return processedItems.contains(itemId);
    }
    
    // Marcar como procesado
    public static void markAsProcessed(Id itemId) {
        processedItems.add(itemId);
    }
    
    // Limpiar para nueva transacción
    public static void reset() {
        isExecuting = false;
        skipEmailTrigger = false;
        processedItems.clear();
        System.debug('🔄 TriggerControl reseteado');
    }
    
    // 🛡️ Verificar si podemos ejecutar el trigger
    public static Boolean canExecuteTrigger() {
        return !isExecuting && !skipEmailTrigger;
    }

    public static void clearProcessedItems() {
        processedItems.clear();
    }
}
public with sharing class ProductCoverageManagerController {
    
    @AuraEnabled(cacheable=true)
    public static List<Product2> getProducts() {
        try {
            return [
                SELECT Id, Name
                FROM Product2
                WHERE IsActive = true
                ORDER BY Name
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error obteniendo productos: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<CoverageType> getCoverages() {
        try {
            return [
                SELECT Id, Name
                FROM CoverageType
                ORDER BY Name
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error obteniendo coberturas: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<Id, Integer> getAssignedCoveragesForMultipleProducts(List<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return new Map<Id, Integer>();
        }
        
        try {
            Map<Id, Integer> coverageCountMap = new Map<Id, Integer>();
            
            // Agrupar por CoverageId y contar cuántos productos tienen cada cobertura
            AggregateResult[] results = [
                SELECT CoverageTypeId, COUNT_DISTINCT(ProductId) productCount
                FROM ProductCoverage
                WHERE ProductId IN :productIds
                GROUP BY CoverageTypeId
            ];
            
            for (AggregateResult result : results) {
                Id coverageId = (Id)result.get('CoverageTypeId');
                Integer count = (Integer)result.get('productCount');
                coverageCountMap.put(coverageId, count);
            }
            
            return coverageCountMap;
        } catch (Exception e) {
            System.debug('Error getting assigned coverages: ' + e.getMessage());
            return new Map<Id, Integer>();
        }
    }
    
    @AuraEnabled
    public static void saveAssignmentsForMultipleProducts(List<Id> productIds, List<Id> coverageIds) {
        // Validaciones
        if (productIds == null || productIds.isEmpty()) {
            throw new AuraHandledException('Debe seleccionar al menos un producto');
        }
        
        if (coverageIds == null) {
            coverageIds = new List<Id>();
        }
        
        Savepoint sp = Database.setSavepoint();
        
        try {
            // 1. Eliminar todas las asignaciones existentes para los productos seleccionados
            List<ProductCoverage> existingAssignments = [
                SELECT Id 
                FROM ProductCoverage
                WHERE ProductId IN :productIds
            ];
            
            if (!existingAssignments.isEmpty()) {
                delete existingAssignments;
                System.debug('Eliminadas ' + existingAssignments.size() + ' asignaciones existentes');
            }
            
            // 2. Crear nuevas asignaciones (producto x cobertura)
            List<ProductCoverage> newAssignments = new List<ProductCoverage>();
            
            for (Id productId : productIds) {
                for (Id coverageId : coverageIds) {
                    if (coverageId != null) {
                        newAssignments.add(new ProductCoverage(
                            ProductId = productId,
                            CoverageTypeId = coverageId
                        ));
                    }
                }
            }
            
            // 3. Insertar nuevas asignaciones
            if (!newAssignments.isEmpty()) {
                insert newAssignments;
                System.debug('Insertadas ' + newAssignments.size() + ' nuevas asignaciones');
            }
            
            System.debug('Guardado exitoso para ' + productIds.size() + ' productos con ' + coverageIds.size() + ' coberturas');
            
        } catch (Exception e) {
            Database.rollback(sp);
            System.debug('Error en saveAssignmentsForMultipleProducts: ' + e.getMessage());
            throw new AuraHandledException('Error al guardar las asignaciones: ' + e.getMessage());
        }
    }
}
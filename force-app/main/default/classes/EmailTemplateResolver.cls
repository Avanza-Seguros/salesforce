public class EmailTemplateResolver {
    
    // Cache para almacenar asignaciones de plantillas por cuenta
    private static Map<Id, Map<String, String>> cuentaTemplateCache = new Map<Id, Map<String, String>>();
    // Cache para nombres de templates a IDs
    private static Map<String, String> templateNameToIdCache = new Map<String, String>();
    
    public static String resolveTemplateName(Items_Cases__c item) {
        System.debug('🔍 === INICIO resolveTemplateName ===');
        System.debug('🔍 Procesando Item: ' + item);
        if (item == null) {
            System.debug('🔍 Item es null');
            return null;
        }
        
        if (item.Nombre_cuenta__c == null) {
            System.debug('🔍 No tiene cuenta asociada');
            return null;
        }
        
        System.debug('🔍 Item ID: ' + item.Id);
        System.debug('🔍 Cuenta ID: ' + item.Nombre_cuenta__c);
        System.debug('🔍 RecordTypeId: ' + item.RecordTypeId);
        System.debug('🔍 Categorias__c: ' + item.Categorias__c);
        
        String recordTypeName = getRecordTypeName(item.RecordTypeId);
        System.debug('🔍 RecordTypeName: ' + recordTypeName);
        
        String categoria = determineCategoria(item, recordTypeName);
        System.debug('🔍 Categoría: ' + categoria);
        
        String templateIdentifier = findAssignedTemplate(item.Nombre_cuenta__c, categoria, recordTypeName);
        System.debug('🔍 Template Identifier encontrado: ' + templateIdentifier);
        
        // **AGREGA ESTE DEBUG CRÍTICO:**
        if (String.isBlank(templateIdentifier)) {
            System.debug('🚨 NO SE ENCONTRÓ TEMPLATE ASIGNADO');
            System.debug('🚨 Cuenta: ' + item.Nombre_cuenta__c);
            System.debug('🚨 Categoría: ' + categoria);
            System.debug('🚨 RecordType: ' + recordTypeName);
            return null;
        }
        
        System.debug('🔍 ¿Es ID (00X...)? ' + templateIdentifier.startsWith('00X'));
        
        if (templateIdentifier.startsWith('00X')) {
            System.debug('✅ Es ID de template: ' + templateIdentifier);
            return templateIdentifier;
        }
        
        System.debug('🔍 Convertiendo DeveloperName a ID: ' + templateIdentifier);
        String templateId = getTemplateIdByName(templateIdentifier);
        System.debug('🔍 ID convertido: ' + templateId);
        
        return templateId;
    }
    
    private static String getTemplateIdByName(String templateName) {
        System.debug('🔍 getTemplateIdByName - INICIO para: ' + templateName);
        // Verificar si ya está en cache
        if (templateNameToIdCache.containsKey(templateName)) {
            System.debug('🔍 Cache hit para templateName: ' + templateName);
            return templateNameToIdCache.get(templateName);
        }
        
        try {
            // Buscar template por DeveloperName o Name
            List<EmailTemplate> templates = [
                SELECT Id, DeveloperName, Name
                FROM EmailTemplate
                WHERE DeveloperName = :templateName
                OR Name = :templateName
                LIMIT 1
            ];
            System.debug('🔍 Templates encontrados: ' + templates.size());
            if (!templates.isEmpty()) {
                System.debug('✅ Template encontrado: ' + templates[0].DeveloperName);
                String templateId = templates[0].Id;
                // Guardar en cache
                System.debug('🔍 Guardando en cache: ' + templateName + ' -> ' + templateId);
                templateNameToIdCache.put(templateName, templateId);
                System.debug('🔍 Cache actualizada: ' + templateNameToIdCache);
                return templateId;
            }
        } catch (Exception e) {
            System.debug('Error buscando template por nombre "' + templateName + '": ' + e.getMessage());
        }
        System.debug('🚨 Template no encontrado para nombre: ' + templateName);
        // Template no encontrado
        return null;
    }
    
    public static String getRecordTypeName(Id recordTypeId) {
        System.debug('::: Iniciando getRecordTypeName :::');
        System.debug('🔍 RecordTypeId: ' + recordTypeId);
        if (recordTypeId == null) return null;
        
        Map<Id, Schema.RecordTypeInfo> recordTypeInfos = Schema.SObjectType.Items_Cases__c.getRecordTypeInfosById();
        Schema.RecordTypeInfo rtInfo = recordTypeInfos.get(recordTypeId);
        System.debug('🔍 RecordTypeInfo: ' + rtInfo);
        return (rtInfo != null) ? rtInfo.getName() : null;
    }
    
    public static String convertRecordTypeToKey(String recordTypeName) {
        System.debug('🔍 convertRecordTypeToKey - INICIO');
        if (String.isBlank(recordTypeName)) return null;
        
        String key = recordTypeName.toUpperCase()
            .replace('Á', 'A')
            .replace('É', 'E')
            .replace('Í', 'I')
            .replace('Ó', 'O')
            .replace('Ú', 'U');
        
        System.debug('🔍 RecordTypeKey generado: ' + key);
        return key;
    }
    
    public static String getTipoGeneralFromRecordType(String recordTypeName) {
        System.debug('🔍 getTipoGeneralFromRecordType - INICIO');
        if (String.isBlank(recordTypeName)) return null;
        
        if (recordTypeName.contains('Alta')) {
            System.debug('✅ Es Alta');
            return 'ALTA';
        } else if (recordTypeName.contains('Baja')) {
            System.debug('✅ Es Baja');
            return 'BAJA';
        } else if (recordTypeName.contains('Cambio')) {
            System.debug('✅ Es Cambio');
            return 'CAMBIO';
        } else if (recordTypeName.contains('Consulta')) {
            System.debug('✅ Es Consulta');
            return 'CONSULTA';
        }
        System.debug('🚨 No se pudo determinar tipo general');
        return null;
    }
    
    public static String determineCategoria(Items_Cases__c item, String recordTypeName) {
        System.debug('🔍 determineCategoria - INICIO');
        System.debug('🔍 Item Categorias__c: ' + item.Categorias__c);
        System.debug('🔍 Baja_Por_Defuncion__c: ' + item.Baja_Por_Defuncion__c);
        System.debug('🔍 RecordTypeName: ' + recordTypeName);
        
        // Primero verificar si hay categoría específica en el item
        if (String.isNotBlank(item.Categorias__c)) {
            System.debug('✅ Usando categoría específica: ' + item.Categorias__c.trim());
            return item.Categorias__c.trim();
        }
        
        if (item.Baja_Por_Defuncion__c == true) {
            System.debug('✅ Es baja por defunción, categoría: 99');
            return '99';
        }
        
        // Lógica para determinar categoría basada en el record type
        if (recordTypeName != null) {
            if (recordTypeName.contains('Alta')) {
                if (recordTypeName.contains('Dependientes')) {
                    System.debug('✅ Es Alta Dependientes, categoría: 02');
                    return '02';
                }
                System.debug('✅ Es Alta, categoría: 00');
                return '00';
            }
            
            if (recordTypeName.contains('Baja')) {
                System.debug('✅ Es Baja, categoría: 01');
                return '01';
            }
            
            if (recordTypeName.contains('Cambio')) {
                if (recordTypeName.contains('Dependientes')) {
                    System.debug('✅ Es Cambio Dependientes, categoría: 22');
                    return '22';
                }
                System.debug('✅ Es Cambio, categoría: 20');
                return '20';
            }
            
            if (recordTypeName.contains('Consulta')) {
                System.debug('✅ Es Consulta, categoría: 30');
                return '30';
            }
        }
        
        // Categoría genérica si no se puede determinar
        System.debug('⚠️ No se pudo determinar categoría, usando: 99');
        return '99';
    }
    
    public static String findAssignedTemplate(Id cuentaId, String categoria, String recordTypeName) {
        System.debug('🔍 findAssignedTemplate - INICIO');
        System.debug('🔍 Cuenta ID: ' + cuentaId);
        System.debug('🔍 Categoría buscada: ' + categoria);
        System.debug('🔍 RecordTypeName: ' + recordTypeName);
        
        // Cargar las plantillas asignadas a la cuenta si no están en cache
        if (!cuentaTemplateCache.containsKey(cuentaId)) {
            System.debug('🔍 Cache miss, cargando asignaciones...');
            loadAccountTemplates(cuentaId);
        } else {
            System.debug('🔍 Cache hit para cuenta');
        }
        
        Map<String, String> templatesForAccount = cuentaTemplateCache.get(cuentaId);
        
        if (templatesForAccount == null || templatesForAccount.isEmpty()) {
            System.debug('🚨 No hay asignaciones de plantilla para esta cuenta');
            return null;
        }
        
        System.debug('🔍 Total asignaciones para cuenta: ' + templatesForAccount.size());
        System.debug('🔍 Keys disponibles: ' + String.join(new List<String>(templatesForAccount.keySet()), ', '));
        
        // Buscar por categoría específica primero
        if (String.isNotBlank(categoria) && templatesForAccount.containsKey(categoria)) {
            System.debug('✅ Encontrado por categoría: ' + categoria);
            return templatesForAccount.get(categoria);
        } else {
            System.debug('❌ No encontrado por categoría: ' + categoria);
        }
        
        // Si no encuentra por categoría, intentar por record type
        String recordTypeKey = convertRecordTypeToKey(recordTypeName);
        System.debug('🔍 Buscando por recordTypeKey: ' + recordTypeKey);
        
        if (String.isNotBlank(recordTypeKey) && templatesForAccount.containsKey(recordTypeKey)) {
            System.debug('✅ Encontrado por recordTypeKey: ' + recordTypeKey);
            return templatesForAccount.get(recordTypeKey);
        }
        
        // Si no encuentra por record type específico, intentar por tipo general
        String tipoGeneral = getTipoGeneralFromRecordType(recordTypeName);
        System.debug('🔍 Buscando por tipoGeneral: ' + tipoGeneral);
        
        if (String.isNotBlank(tipoGeneral) && templatesForAccount.containsKey(tipoGeneral)) {
            System.debug('✅ Encontrado por tipoGeneral: ' + tipoGeneral);
            return templatesForAccount.get(tipoGeneral);
        }
        
        System.debug('🚨 No se encontró ninguna plantilla asignada');
        return null;
    }
    
    public static void loadAccountTemplates(Id cuentaId) {
        System.debug('🔍 loadAccountTemplates - INICIO para cuenta: ' + cuentaId);
        Map<String, String> templatesMap = new Map<String, String>();
        
        try {
            // Buscar todas las asignaciones de plantilla para esta empresa
            List<Asigacion_de_plantilla__c> asignaciones = [
                SELECT Id, Categoria__c, ID_de_la_plantilla__c, Empresa__c, Name
                FROM Asigacion_de_plantilla__c 
                WHERE Empresa__c = :cuentaId
                ORDER BY Name
            ];
            
            System.debug('🔍 Asignaciones encontradas en BD: ' + asignaciones.size());
            
            for (Asigacion_de_plantilla__c asignacion : asignaciones) {
                System.debug('🔍 Asignación: ' + asignacion.Name + 
                            ' | Categoría: ' + asignacion.Categoria__c + 
                            ' | Template ID: ' + asignacion.ID_de_la_plantilla__c);
                
                String categoria = asignacion.Categoria__c;
                String templateId = asignacion.ID_de_la_plantilla__c;
                
                if (String.isNotBlank(categoria) && String.isNotBlank(templateId)) {
                    templatesMap.put(categoria.trim(), templateId.trim());
                    System.debug('✅ Agregado: ' + categoria.trim() + ' -> ' + templateId.trim());
                    
                    if (String.isNotBlank(asignacion.Name)) {
                        templatesMap.put(asignacion.Name.trim(), templateId.trim());
                        System.debug('✅ Agregado por nombre: ' + asignacion.Name.trim() + ' -> ' + templateId.trim());
                    }
                }
            }
        } catch (Exception e) {
            System.debug('🔥 Error cargando asignaciones: ' + e.getMessage());
        }
        
        System.debug('🔍 Total en templatesMap: ' + templatesMap.size());
        cuentaTemplateCache.put(cuentaId, templatesMap);
    }
    
    public static EmailTemplate resolveTemplate(Items_Cases__c item) {
        System.debug('🔍 === INICIO resolveTemplate ===');
        System.debug('🔍 Procesando Item: ' + item);
        String templateId = resolveTemplateName(item);
        System.debug('🔍 Template ID resuelto: ' + templateId);

        // Si no se encontró template, devolver null
        if (String.isBlank(templateId)) {
            System.debug('🔍 No se encontró template ID');
            return null;
        }
        
        try {
             List<EmailTemplate> templates = new List<EmailTemplate>();
            if(item.Tipo_de_peticion__c == 'Baja') {
                templates = [
                    SELECT Id, Subject, Body, HtmlValue, DeveloperName, Name, IsActive
                    FROM EmailTemplate
                    WHERE DeveloperName = :'Bajas'  // Buscar por ID, no por DeveloperName
                    LIMIT 1
                ];
            } else {
                // Buscar el template por ID
                templates = [
                    SELECT Id, Subject, Body, HtmlValue, DeveloperName, Name, IsActive
                    FROM EmailTemplate 
                    WHERE Id = :templateId
                    AND IsActive = true
                    LIMIT 1
                ];
            }
            System.debug('🔍 Templates encontrados por ID: ' + templates.size());
            if (!templates.isEmpty()) {
                System.debug('✅ Template encontrado: ' + templates[0].DeveloperName);
                return templates[0];
            }
            
            System.debug('🔍 Template no encontrado por ID, intentando por DeveloperName/Name');
            
            // Si no se encontró por ID, intentar por DeveloperName o Name
            templates = [
                SELECT Id, Subject, Body, HtmlValue, DeveloperName, Name, IsActive
                FROM EmailTemplate 
                WHERE (DeveloperName = :templateId OR Name = :templateId)
                AND IsActive = true
                LIMIT 1
            ];
            
            System.debug('🔍 Templates encontrados por nombre: ' + templates.size());
            
            return templates.isEmpty() ? null : templates[0];
            
        } catch (Exception e) {
            System.debug('🔥 Error resolviendo plantilla: ' + e.getMessage());
            return null;
        }
    }
    
    public static void preloadAccountTemplates(Id cuentaId) {
        System.debug('🔍 preloadAccountTemplates::: ');
        if (!cuentaTemplateCache.containsKey(cuentaId)) {
            System.debug('🔍 Cargando plantillas para cuenta: ' + cuentaId);
            loadAccountTemplates(cuentaId);
        }
    }
    
    public static void clearCache() {
        System.debug('🧹 Limpiando cache de EmailTemplateResolver');
        cuentaTemplateCache.clear();
        templateNameToIdCache.clear();
    }
    
    public static Set<String> getRequiredTemplateIds(List<Items_Cases__c> items) {
        System.debug('🔍 === INICIO getRequiredTemplateIds ===');
        System.debug('🔍 Total items a procesar: ' + items.size());
        Set<String> templateIds = new Set<String>();
        
        if (items == null || items.isEmpty()) {
            System.debug('⚠️ No hay items para procesar');
            return templateIds;
        }
        
        // Agrupar items por cuenta
        Map<Id, List<Items_Cases__c>> itemsByAccount = new Map<Id, List<Items_Cases__c>>();
        
        for (Items_Cases__c item : items) {
            System.debug('🔍 Procesando item: ' + item.Id + ' | Cuenta: ' + item.Nombre_cuenta__c);
            if (item.Nombre_cuenta__c != null) {
                System.debug('🔍 Agregando item a cuenta: ' + item.Nombre_cuenta__c);
                if (!itemsByAccount.containsKey(item.Nombre_cuenta__c)) {
                    System.debug('🔍 Nueva cuenta encontrada en itemsByAccount: ' + item.Nombre_cuenta__c);
                    itemsByAccount.put(item.Nombre_cuenta__c, new List<Items_Cases__c>());
                }
                itemsByAccount.get(item.Nombre_cuenta__c).add(item);
                System.debug('✅ Item agregado a cuenta: ' + item.Id);
            }
        }
        System.debug('🔍 Total cuentas únicas: ' + itemsByAccount.size());
        // Resolver templates para cada cuenta
        for (Id cuentaId : itemsByAccount.keySet()) {
            System.debug('🔍 Procesando cuenta: ' + cuentaId);
            preloadAccountTemplates(cuentaId);
            
            for (Items_Cases__c item : itemsByAccount.get(cuentaId)) {
                String templateId = resolveTemplateName(item);
                if (String.isNotBlank(templateId)) {
                    System.debug('✅ Agregando template ID requerido: ' + templateId + ' para item: ' + item.Id);
                    templateIds.add(templateId);
                }
            }
        }
        
        return templateIds;
    }
    
    public static void debugAccountAssignments(Id cuentaId) {
        System.debug('🔍 debugAccountAssignments - INICIO para cuenta: ' + cuentaId);
        if (!cuentaTemplateCache.containsKey(cuentaId)) {
            System.debug('🔍 Cache miss, cargando asignaciones...');
            loadAccountTemplates(cuentaId);
        }
        
        Map<String, String> templates = cuentaTemplateCache.get(cuentaId);
        if (templates != null) {
            System.debug('=== ASIGNACIONES DE PLANTILLA PARA CUENTA ' + cuentaId + ' ===');
            for (String key : templates.keySet()) {
                System.debug(key + ' => ' + templates.get(key));
            }
            
            if (templates.isEmpty()) {
                System.debug('No hay asignaciones de plantilla para esta cuenta');
            }
        } else {
            System.debug('No se encontraron asignaciones de plantilla para esta cuenta');
        }
    }
    
    // Método auxiliar para debug
    public static String debugResolveTemplate(Items_Cases__c item) {
        System.debug('🔍 debugResolveTemplate - INICIO');
        if (item == null) return 'Item es null';
        if (item.Nombre_cuenta__c == null) return 'No tiene cuenta asociada';
        
        String recordTypeName = getRecordTypeName(item.RecordTypeId);
        System.debug('🔍 RecordTypeName: ' + recordTypeName);
        String categoria = determineCategoria(item, recordTypeName);
        System.debug('🔍 Categoría: ' + categoria);
        
        return String.format(
            'Cuenta: {0}, RecordType: {1}, Categoría: {2}, Template Encontrado: {3}',
            new String[]{
                item.Nombre_cuenta__c,
                recordTypeName,
                categoria,
                resolveTemplateName(item)
            }
        );
    }
}
/**
 * @description Maneja los asegurados de una oportunidad COLECTIVA.
 *              Los asegurados se guardan como Rol de Contacto de Oportunidad
 *              (OpportunityContactRole, estandar) con los campos Parentesco__c,
 *              Fecha_de_Nacimiento__c y Edad__c. Al emitir la poliza, se copian
 *              a Participante de Poliza (InsurancePolicyParticipant, FSC).
 */
public with sharing class AseguradosController {

    // ============================================================
    // Wrapper de salida hacia el LWC
    // ============================================================
    public class AseguradoRow {
        @AuraEnabled public Id ocrId;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String nombre;
        @AuraEnabled public String parentesco;
        @AuraEnabled public Date fechaNacimiento;
        @AuraEnabled public Decimal edad;
        @AuraEnabled public String email;
        @AuraEnabled public String telefono;
        @AuraEnabled public String rfc;
        @AuraEnabled public Boolean isPrincipal;
    }

    // ============================================================
    // LISTAR asegurados de una oportunidad
    // ============================================================
    @AuraEnabled(cacheable=false)
    public static List<AseguradoRow> getAsegurados(Id opportunityId) {
        List<AseguradoRow> out = new List<AseguradoRow>();
        if (opportunityId == null) { return out; }
        try {
            for (OpportunityContactRole ocr : [
                SELECT Id, ContactId, Contact.Name, Contact.Email, Contact.Phone, Contact.RFC__c,
                       IsPrimary, Parentesco__c, Fecha_de_Nacimiento__c, Edad__c
                FROM OpportunityContactRole
                WHERE OpportunityId = :opportunityId
                ORDER BY IsPrimary DESC, Contact.Name
            ]) {
                AseguradoRow r = new AseguradoRow();
                r.ocrId = ocr.Id;
                r.contactId = ocr.ContactId;
                r.nombre = ocr.Contact != null ? ocr.Contact.Name : null;
                r.parentesco = ocr.Parentesco__c;
                r.fechaNacimiento = ocr.Fecha_de_Nacimiento__c;
                r.edad = ocr.Edad__c;
                r.email = ocr.Contact != null ? ocr.Contact.Email : null;
                r.telefono = ocr.Contact != null ? ocr.Contact.Phone : null;
                r.rfc = ocr.Contact != null ? ocr.Contact.RFC__c : null;
                r.isPrincipal = ocr.IsPrimary;
                out.add(r);
            }
        } catch (Exception e) {
            throw new AuraHandledException('No se pudieron cargar los asegurados: ' + errMsg(e));
        }
        return out;
    }

    // ============================================================
    // GUARDAR (alta masiva o manual) de asegurados
    //   aseguradosJson: [{ contactId, nombreCompleto|nombre/apellidoPaterno/apellidoMaterno,
    //                       rfc, email, telefono, parentesco, fechaNacimiento(yyyy-mm-dd), edad }]
    //   Devuelve cuantos asegurados quedaron ligados.
    // ============================================================
    @AuraEnabled(cacheable=false)
    public static Integer guardarAsegurados(Id opportunityId, String aseguradosJson) {
        if (opportunityId == null || String.isBlank(aseguradosJson)) { return 0; }
        try {
            Opportunity opp = [SELECT Id, AccountId FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
            Id accId = opp.AccountId;

            List<Object> filas = (List<Object>) JSON.deserializeUntyped(aseguradosJson);
            if (filas == null || filas.isEmpty()) { return 0; }

            // 1) Normaliza filas y junta llaves para buscar contactos existentes.
            List<Map<String, Object>> rows = new List<Map<String, Object>>();
            Set<String> emails = new Set<String>();
            Set<String> rfcs   = new Set<String>();
            Set<String> nombres = new Set<String>();
            for (Object o : filas) {
                if (!(o instanceof Map<String, Object>)) { continue; }
                Map<String, Object> m = (Map<String, Object>) o;
                m.put('_nombre', armarNombre(m));
                rows.add(m);
                String em = lower(str(m, 'email'));
                String rf = upper(str(m, 'rfc'));
                String nm = str(m, '_nombre');
                if (String.isNotBlank(em)) { emails.add(em); }
                if (String.isNotBlank(rf)) { rfcs.add(rf); }
                if (String.isNotBlank(nm)) { nombres.add(nm); }
            }

            // 2) Contactos existentes por email / RFC / nombre (bajo la cuenta).
            Map<String, Id> porEmail  = new Map<String, Id>();
            Map<String, Id> porRfc    = new Map<String, Id>();
            Map<String, Id> porNombre = new Map<String, Id>();
            if (!emails.isEmpty() || !rfcs.isEmpty() || !nombres.isEmpty()) {
                for (Contact c : [
                    SELECT Id, Name, Email, RFC__c, AccountId
                    FROM Contact
                    WHERE Email IN :emails OR RFC__c IN :rfcs
                          OR (AccountId = :accId AND Name IN :nombres)
                    LIMIT 5000
                ]) {
                    if (String.isNotBlank(c.Email))  { porEmail.put(c.Email.toLowerCase(), c.Id); }
                    if (String.isNotBlank(c.RFC__c)) { porRfc.put(c.RFC__c.toUpperCase(), c.Id); }
                    if (String.isNotBlank(c.Name))   { porNombre.put(c.Name, c.Id); }
                }
            }

            // 3) Resuelve cada fila a un ContactId; crea los que falten.
            List<Contact> nuevos = new List<Contact>();
            List<Map<String, Object>> pendientes = new List<Map<String, Object>>();
            for (Map<String, Object> m : rows) {
                Id cid = strId(m, 'contactId');
                if (cid == null) { cid = porEmail.get(lower(str(m, 'email'))); }
                if (cid == null) { cid = porRfc.get(upper(str(m, 'rfc'))); }
                if (cid == null) { cid = porNombre.get(str(m, '_nombre')); }
                if (cid != null) {
                    m.put('_contactId', cid);
                } else {
                    Contact c = construirContacto(m, accId);
                    if (c != null) { nuevos.add(c); pendientes.add(m); }
                }
            }
            if (!nuevos.isEmpty()) {
                insert nuevos;
                for (Integer i = 0; i < nuevos.size(); i++) {
                    pendientes[i].put('_contactId', nuevos[i].Id);
                }
            }

            // 4) OCR existentes de la oportunidad (para no duplicar).
            Map<Id, OpportunityContactRole> ocrPorContacto = new Map<Id, OpportunityContactRole>();
            for (OpportunityContactRole ex : [
                SELECT Id, ContactId FROM OpportunityContactRole WHERE OpportunityId = :opportunityId
            ]) {
                if (ex.ContactId != null) { ocrPorContacto.put(ex.ContactId, ex); }
            }

            // 5) Arma/actualiza los OCR. Solo un principal.
            Boolean yaHayPrincipal = false;
            for (OpportunityContactRole ex : ocrPorContacto.values()) {
                if (ex.IsPrimary == true) { yaHayPrincipal = true; }
            }
            List<OpportunityContactRole> aInsertar = new List<OpportunityContactRole>();
            List<OpportunityContactRole> aActualizar = new List<OpportunityContactRole>();
            Set<Id> vistos = new Set<Id>();
            for (Map<String, Object> m : rows) {
                Id cid = strId(m, '_contactId');
                if (cid == null || vistos.contains(cid)) { continue; }
                vistos.add(cid);

                String parentesco = str(m, 'parentesco');
                Date fnac = parseDate(str(m, 'fechaNacimiento'));
                Decimal edad = calcularEdad(fnac, num(m, 'edad'));
                Boolean esTitular = parentesco == 'Contratante' || parentesco == 'Asegurado titular';
                Boolean principal = false;
                if (esTitular && !yaHayPrincipal) { principal = true; yaHayPrincipal = true; }

                OpportunityContactRole ocr = ocrPorContacto.containsKey(cid)
                    ? ocrPorContacto.get(cid) : new OpportunityContactRole(
                        OpportunityId = opportunityId, ContactId = cid);
                if (String.isNotBlank(parentesco)) { ocr.Parentesco__c = parentesco; }
                if (fnac != null) { ocr.Fecha_de_Nacimiento__c = fnac; }
                if (edad != null) { ocr.Edad__c = edad; }
                if (principal) { ocr.IsPrimary = true; }

                if (ocr.Id == null) { aInsertar.add(ocr); } else { aActualizar.add(ocr); }
            }
            if (!aActualizar.isEmpty()) { update aActualizar; }
            if (!aInsertar.isEmpty())   { insert aInsertar; }

            return [SELECT COUNT() FROM OpportunityContactRole WHERE OpportunityId = :opportunityId];
        } catch (Exception e) {
            throw new AuraHandledException('No se pudieron guardar los asegurados: ' + errMsg(e));
        }
    }

    // ============================================================
    // ELIMINAR un asegurado (quita el rol; no borra el contacto).
    // ============================================================
    @AuraEnabled(cacheable=false)
    public static void eliminarAsegurado(Id ocrId) {
        if (ocrId == null) { return; }
        try {
            delete [SELECT Id FROM OpportunityContactRole WHERE Id = :ocrId LIMIT 1];
        } catch (Exception e) {
            throw new AuraHandledException('No se pudo quitar el asegurado: ' + errMsg(e));
        }
    }

    // ============================================================
    // COPIAR asegurados de la oportunidad a la Poliza (FSC).
    //   Crea un InsurancePolicyParticipant por asegurado (rol Asegurado).
    // ============================================================
    @AuraEnabled(cacheable=false)
    public static Integer copiarAseguradosAPoliza(Id opportunityId, Id policyId) {
        if (opportunityId == null || policyId == null) { return 0; }
        try {
            List<OpportunityContactRole> ocrs = [
                SELECT Id, ContactId, Contact.Name, IsPrimary, Parentesco__c
                FROM OpportunityContactRole
                WHERE OpportunityId = :opportunityId AND ContactId != null
            ];
            if (ocrs.isEmpty()) { return 0; }

            // Ya existentes (no duplicar) por contacto.
            Set<Id> yaConParticipante = new Set<Id>();
            for (InsurancePolicyParticipant p : [
                SELECT PrimaryParticipantContactId
                FROM InsurancePolicyParticipant
                WHERE InsurancePolicyId = :policyId AND PrimaryParticipantContactId != null
            ]) {
                yaConParticipante.add(p.PrimaryParticipantContactId);
            }

            Schema.DescribeFieldResult roleF = InsurancePolicyParticipant.Role.getDescribe();
            Schema.DescribeFieldResult relF  = InsurancePolicyParticipant.RelationshipToInsured.getDescribe();
            String rolAsegurado = pick(roleF, new List<String>{
                'Insured', 'Covered Party', 'Covered', 'Asegurado', 'Insured Party', 'Named Insured' });

            List<InsurancePolicyParticipant> nuevos = new List<InsurancePolicyParticipant>();
            for (OpportunityContactRole ocr : ocrs) {
                if (yaConParticipante.contains(ocr.ContactId)) { continue; }
                InsurancePolicyParticipant p = new InsurancePolicyParticipant();
                p.InsurancePolicyId = policyId;
                p.PrimaryParticipantContactId = ocr.ContactId;
                if (ocr.Contact != null) { p.ParticipantName = ocr.Contact.Name; }
                if (String.isNotBlank(rolAsegurado)) { p.Role = rolAsegurado; }
                Boolean esContratante = ocr.Parentesco__c == 'Contratante' || ocr.IsPrimary == true;
                p.IsPolicyholder = esContratante;
                String rel = mapRelacion(relF, ocr.Parentesco__c);
                if (String.isNotBlank(rel)) { p.RelationshipToInsured = rel; }
                try { p.EffectiveDate = Date.today(); } catch (Exception ignore) {}
                nuevos.add(p);
            }
            if (!nuevos.isEmpty()) { insert nuevos; }
            return nuevos.size();
        } catch (Exception e) {
            throw new AuraHandledException('No se pudieron copiar los asegurados a la poliza: ' + errMsg(e));
        }
    }

    // ============================================================
    // Helpers
    // ============================================================
    private static String armarNombre(Map<String, Object> m) {
        String completo = str(m, 'nombreCompleto');
        if (String.isBlank(completo)) { completo = str(m, 'nombre'); }
        List<String> ps = new List<String>();
        if (String.isNotBlank(str(m, 'nombre')) && String.isBlank(str(m, 'nombreCompleto'))) {
            ps.add(str(m, 'nombre'));
            if (String.isNotBlank(str(m, 'apellidoPaterno'))) { ps.add(str(m, 'apellidoPaterno')); }
            if (String.isNotBlank(str(m, 'apellidoMaterno'))) { ps.add(str(m, 'apellidoMaterno')); }
            return String.join(ps, ' ').trim();
        }
        return String.isBlank(completo) ? '' : completo.trim();
    }

    private static Contact construirContacto(Map<String, Object> m, Id accId) {
        String nombre  = str(m, 'nombre');
        String paterno = str(m, 'apellidoPaterno');
        String materno = str(m, 'apellidoMaterno');
        String completo = str(m, 'nombreCompleto');
        if (String.isBlank(completo)) { completo = str(m, '_nombre'); }

        Contact c = new Contact();
        if (accId != null) { c.AccountId = accId; }

        if (String.isNotBlank(nombre) || String.isNotBlank(paterno) || String.isNotBlank(materno)) {
            String last = String.isNotBlank(materno) ? materno : paterno;
            if (String.isBlank(last)) { last = nombre; }
            if (String.isNotBlank(nombre)) { c.FirstName = nombre; }
            if (String.isNotBlank(paterno) && String.isNotBlank(materno)) {
                try { c.put('MiddleName', paterno); } catch (Exception ignore) {}
            }
            c.LastName = last;
        } else if (String.isNotBlank(completo)) {
            List<String> partes = completo.trim().split('\\s+');
            if (partes.size() > 1) {
                c.LastName = partes[partes.size() - 1];
                List<String> first = new List<String>();
                for (Integer i = 0; i < partes.size() - 1; i++) { first.add(partes[i]); }
                c.FirstName = String.join(first, ' ');
            } else {
                c.LastName = completo.trim();
            }
        } else {
            return null; // sin nombre no se puede crear
        }

        if (String.isNotBlank(str(m, 'email')))    { c.Email = str(m, 'email'); }
        if (String.isNotBlank(str(m, 'telefono'))) { c.Phone = str(m, 'telefono'); }
        if (String.isNotBlank(str(m, 'rfc'))) {
            try { c.put('RFC__c', str(m, 'rfc').toUpperCase()); } catch (Exception ignore) {}
        }
        return c;
    }

    private static Decimal calcularEdad(Date fnac, Decimal edadDada) {
        if (fnac != null) {
            Date hoy = Date.today();
            Integer edad = hoy.year() - fnac.year();
            if (hoy.month() < fnac.month() ||
               (hoy.month() == fnac.month() && hoy.day() < fnac.day())) { edad--; }
            return edad >= 0 ? edad : null;
        }
        return edadDada;
    }

    private static Date parseDate(String s) {
        if (String.isBlank(s)) { return null; }
        String t = s.trim();
        try { return Date.valueOf(t); } catch (Exception e) {}
        // dd/mm/yyyy
        try {
            if (t.contains('/')) {
                List<String> p = t.split('/');
                if (p.size() == 3) {
                    Integer d = Integer.valueOf(p[0]);
                    Integer mo = Integer.valueOf(p[1]);
                    Integer y = Integer.valueOf(p[2]);
                    if (y < 100) { y += 1900; }
                    return Date.newInstance(y, mo, d);
                }
            }
        } catch (Exception e) {}
        return null;
    }

    private static String mapRelacion(Schema.DescribeFieldResult f, String parentesco) {
        if (String.isBlank(parentesco)) { return null; }
        Map<String, List<String>> cand = new Map<String, List<String>>{
            'Contratante'       => new List<String>{ 'Self', 'Insured', 'Titular', 'Same', 'Policyholder' },
            'Asegurado titular' => new List<String>{ 'Self', 'Insured', 'Titular', 'Same' },
            'Conyuge'           => new List<String>{ 'Spouse', 'Conyuge', 'Cónyuge', 'Partner' },
            'Hijo'              => new List<String>{ 'Child', 'Son', 'Daughter', 'Hijo', 'Dependent' },
            'Padre o Madre'     => new List<String>{ 'Parent', 'Father', 'Mother', 'Padre', 'Madre' },
            'Empleado'          => new List<String>{ 'Employee', 'Empleado', 'Other' },
            'Otro'              => new List<String>{ 'Other', 'Otro' }
        };
        List<String> opciones = cand.containsKey(parentesco) ? cand.get(parentesco) : new List<String>{ 'Other' };
        return pick(f, opciones);
    }

    // Devuelve el primer valor de picklist activo que coincida (ignora mayus/acentos basicos).
    private static String pick(Schema.DescribeFieldResult f, List<String> candidatos) {
        Set<String> activos = new Set<String>();
        for (Schema.PicklistEntry pe : f.getPicklistValues()) {
            if (pe.isActive()) { activos.add(pe.getValue()); }
        }
        for (String cand : candidatos) {
            for (String a : activos) {
                if (a.equalsIgnoreCase(cand)) { return a; }
            }
        }
        return null;
    }

    private static String str(Map<String, Object> m, String k) {
        Object v = (m != null) ? m.get(k) : null;
        return v == null ? null : String.valueOf(v).trim();
    }
    private static Decimal num(Map<String, Object> m, String k) {
        Object v = (m != null) ? m.get(k) : null;
        if (v == null) { return null; }
        try { return Decimal.valueOf(String.valueOf(v)); } catch (Exception e) { return null; }
    }
    private static Id strId(Map<String, Object> m, String k) {
        String s = str(m, k);
        if (String.isBlank(s)) { return null; }
        try { return (Id) s; } catch (Exception e) { return null; }
    }
    private static String lower(String s) { return String.isBlank(s) ? s : s.toLowerCase(); }
    private static String upper(String s) { return String.isBlank(s) ? s : s.toUpperCase(); }

    private static String errMsg(Exception e) {
        String m = e.getMessage();
        if (e instanceof DmlException && ((DmlException) e).getNumDml() > 0) {
            m = ((DmlException) e).getDmlMessage(0);
        }
        return m;
    }
}

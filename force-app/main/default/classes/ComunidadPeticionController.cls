/**
 * @description Controlador para el portal de comunidad: permite al usuario buscar
 *              entre las polizas a las que tiene acceso, ver los contactos/certificados
 *              relacionados (Poliza_Contacto__c) y generar una Peticion (Items_Cases__c).
 *              Usa "with sharing" para que el usuario de comunidad solo vea SUS polizas
 *              y los contactos de esas polizas (Poliza_Contacto__c es ControlledByParent).
 */
public with sharing class ComunidadPeticionController {

    // ============================================================
    // Wrappers
    // ============================================================
    public class PolizaOpc {
        @AuraEnabled public Id id;
        @AuraEnabled public String numero;
        @AuraEnabled public String nombre;
        @AuraEnabled public String contratante;
        @AuraEnabled public String tipo;
        @AuraEnabled public String label;
    }

    public class ContactoPoliza {
        @AuraEnabled public Id id;            // Id del Poliza_Contacto__c (certificado)
        @AuraEnabled public Id contactoId;
        @AuraEnabled public String nombre;
        @AuraEnabled public Date fechaNacimiento;
        @AuraEnabled public String certificado;
        @AuraEnabled public String parentesco;
        @AuraEnabled public String categoria;
        @AuraEnabled public Date fechaAlta;
        @AuraEnabled public Date fechaBaja;
        @AuraEnabled public Boolean activo;
    }

    // ============================================================
    // 1) Buscar las polizas del usuario (por numero, nombre o contratante)
    // ============================================================
    @AuraEnabled(cacheable=false)
    public static List<PolizaOpc> buscarMisPolizas(String termino) {
        List<PolizaOpc> out = new List<PolizaOpc>();
        String t = (termino == null) ? '' : termino.trim();
        // Con termino corto no filtra por texto: muestra las primeras accesibles.
        String filtro = '%' + t + '%';
        List<Polizas__c> polizas;
        if (t.length() >= 2) {
            polizas = [
                SELECT Id, Name, Numero_Polizas__c, Nombre_contratante__c, Tipo_de_poliza__c
                FROM Polizas__c
                WHERE Name LIKE :filtro
                   OR Numero_Polizas__c LIKE :filtro
                   OR Nombre_contratante__c LIKE :filtro
                ORDER BY Name
                LIMIT 50
            ];
        } else {
            polizas = [
                SELECT Id, Name, Numero_Polizas__c, Nombre_contratante__c, Tipo_de_poliza__c
                FROM Polizas__c
                ORDER BY LastModifiedDate DESC
                LIMIT 50
            ];
        }
        for (Polizas__c p : polizas) {
            PolizaOpc o = new PolizaOpc();
            o.id = p.Id;
            o.numero = p.Numero_Polizas__c;
            o.nombre = p.Name;
            o.contratante = p.Nombre_contratante__c;
            o.tipo = (p.Tipo_de_poliza__c != null) ? String.valueOf(p.Tipo_de_poliza__c) : '';
            String etiqueta = p.Name;
            o.label = etiqueta;
            out.add(o);
        }
        return out;
    }

    // ============================================================
    // 1.b) Todas las polizas del usuario (para el picklist), por nombre
    // ============================================================
    @AuraEnabled(cacheable=true)
    public static List<PolizaOpc> getMisPolizas() {
        List<PolizaOpc> out = new List<PolizaOpc>();
        for (Polizas__c p : [
            SELECT Id, Name, Numero_Polizas__c, Nombre_contratante__c, Tipo_de_poliza__c
            FROM Polizas__c
            ORDER BY Name
            LIMIT 1000
        ]) {
            PolizaOpc o = new PolizaOpc();
            o.id = p.Id;
            o.numero = p.Numero_Polizas__c;
            o.nombre = p.Name;
            o.contratante = p.Nombre_contratante__c;
            o.tipo = (p.Tipo_de_poliza__c != null) ? String.valueOf(p.Tipo_de_poliza__c) : '';
            String etiqueta = p.Name;
            o.label = etiqueta;
            out.add(o);
        }
        return out;
    }

    // ============================================================
    // 2) Contactos/certificados de una poliza
    // ============================================================
    @AuraEnabled(cacheable=false)
    public static List<ContactoPoliza> getContactosDePoliza(Id polizaId) {
        List<ContactoPoliza> out = new List<ContactoPoliza>();
        if (polizaId == null) { return out; }
        for (Poliza_Contacto__c pc : [
            SELECT Id, Contacto__c, Contacto__r.Name, Contacto__r.Birthdate,
                   Certificado__c, Parentesco__c, Categoria__c,
                   Fecha_de_alta__c, Fecha_de_baja__c
            FROM Poliza_Contacto__c
            WHERE Poliza__c = :polizaId
            ORDER BY Contacto__r.Name
            LIMIT 2000
        ]) {
            ContactoPoliza c = new ContactoPoliza();
            c.id = pc.Id;
            c.contactoId = pc.Contacto__c;
            c.nombre = (pc.Contacto__r != null) ? pc.Contacto__r.Name : '';
            c.fechaNacimiento = (pc.Contacto__r != null) ? pc.Contacto__r.Birthdate : null;
            c.certificado = pc.Certificado__c;
            c.parentesco = (pc.Parentesco__c != null) ? String.valueOf(pc.Parentesco__c) : '';
            c.categoria = (pc.Categoria__c != null) ? String.valueOf(pc.Categoria__c) : '';
            c.fechaAlta = pc.Fecha_de_alta__c;
            c.fechaBaja = pc.Fecha_de_baja__c;
            c.activo = (pc.Fecha_de_baja__c == null);
            out.add(c);
        }
        return out;
    }

    // ============================================================
    // 3) Crear una Peticion (Items_Cases__c) para un contacto/certificado
    //    tipo: 'Alta' | 'Baja' | 'Cambio'
    // ============================================================
    @AuraEnabled
    public static Id crearPeticion(Id polizaId, Id certificadoId, String tipo, Date fechaNacimiento) {
        try {
            if (polizaId == null || certificadoId == null) {
                throw new AuraHandledException('Falta la poliza o el contacto para crear la peticion.');
            }
            if (String.isBlank(tipo)) { tipo = 'Cambio'; }

            // Datos del certificado seleccionado.
            Poliza_Contacto__c cert = [
                SELECT Id, Contacto__c, Contacto__r.Birthdate, Certificado__c
                FROM Poliza_Contacto__c
                WHERE Id = :certificadoId
                LIMIT 1
            ];

            Date fnac = (fechaNacimiento != null) ? fechaNacimiento : cert.Contacto__r.Birthdate;

            Items_Cases__c it = new Items_Cases__c();
            it.Poliza__c = polizaId;
            it.Relacion_de_certificado__c = cert.Id;
            it.Contacto__c = cert.Contacto__c;
            it.Asegurado__c = cert.Contacto__c;
            it.Certificado__c = cert.Certificado__c;
            it.Tipo_de_peticion__c = tipo;
            it.Estatus__c = 'Nuevo';
            it.Fecha_de_peticion__c = Date.today();
            if (fnac != null) { it.Fecha_de_nacimiento__c = fnac; }

            Id rt = recordTypeIdPorTipo(tipo);
            if (rt != null) { it.RecordTypeId = rt; }

            insert it;
            return it.Id;

        } catch (DmlException e) {
            throw new AuraHandledException(mensajeDml(e));
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('No se pudo crear la peticion: ' + e.getMessage());
        }
    }

    // ============================================================
    // Helpers
    // ============================================================
    private static Id recordTypeIdPorTipo(String tipo) {
        Map<String, Schema.RecordTypeInfo> rts =
            Items_Cases__c.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();
        // Nombres de desarrollador esperados: Alta, Baja, Cambio.
        String dev = tipo;
        if (rts.containsKey(dev) && rts.get(dev).isAvailable()) {
            return rts.get(dev).getRecordTypeId();
        }
        return null;
    }

    private static String mensajeDml(DmlException e) {
        // Devuelve el primer mensaje de regla de validacion / error, legible.
        if (e.getNumDml() > 0) { return e.getDmlMessage(0); }
        return e.getMessage();
    }
}

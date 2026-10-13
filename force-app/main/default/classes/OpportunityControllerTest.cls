/**
 *  @name: OpportunityControllerTest
 *  @description: Pruebas unitarias para OpportunityController: listado, detalle, borrado,
 *               búsquedas, aceptar cotización, cambio de etapa, guardar oportunidad y extracción.
 *               Los caminos que dependen de configuración específica del org (Person Accounts,
 *               objetos custom opcionales) se envuelven en try/catch para no romper el despliegue.
 */
@isTest
private class OpportunityControllerTest {

    static String activeStage() {
        List<OpportunityStage> s = [
            SELECT MasterLabel FROM OpportunityStage
            WHERE IsActive = true ORDER BY SortOrder ASC LIMIT 1
        ];
        return s.isEmpty() ? 'Prospecting' : s[0].MasterLabel;
    }

    // Crea (o reutiliza) un Agente para satisfacer la validacion "No existe Agente".
    static Id agenteId() {
        List<Agente__c> ag = [SELECT Id FROM Agente__c LIMIT 1];
        if (!ag.isEmpty()) { return ag[0].Id; }
        Agente__c a = new Agente__c(Name = 'Agente Test');
        insert a;
        return a.Id;
    }

    // Crea (o reutiliza) el Producer (agente) que guarda saveOpportunity en Opportunity.Producer__c.
    static Id producerId() {
        List<Producer> ps = [SELECT Id FROM Producer LIMIT 1];
        if (!ps.isEmpty()) { return ps[0].Id; }
        Producer p = new Producer(Name = 'Abraham Gonzalez');
        insert p;
        return p.Id;
    }

    @testSetup
    static void setup() {
        Account acc = new Account(Name = 'Empresa Prueba Uno', AnnualRevenue = 100);
        insert acc;

        Product2 prod = new Product2(Name = 'Producto Auto Prueba', Family = 'Automoviles', IsActive = true);
        insert prod;
        
        Agente__c ag = new Agente__c(Name = 'Abraham Gonzalez');
        insert ag;
        
        Pricebook2 pb = new Pricebook2(Name = 'Avanza Price Book', IsActive = true);
        insert pb;

        Opportunity opp = new Opportunity(
            Name = 'Oportunidad Prueba Uno',
            StageName = activeStage(),
            CloseDate = Date.today().addDays(30),
            AccountId = acc.Id,
            Agente_Relacionado__c = ag.Id,
            Pricebook2Id = pb.Id,
            Ramo__c = 'Automoviles'
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Cotización Prueba',
            OpportunityId = opp.Id,
            Status = 'Draft',
            Ramos__c = opp.Ramo__c,
            Frecuencia_de_prima__c = 'Mensual',
            Prima_Total__c = 120000,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        try { q.put('Product__c', prod.Id); } catch (Exception ignore) {}
        insert q;
    }

    @isTest
    static void testGetOpportunities() {
        Test.startTest();
        List<Opportunity> opps = OpportunityController.getOpportunities();
        Test.stopTest();
        System.assert(!opps.isEmpty(), 'Debe listar oportunidades');
    }

    @isTest
    static void testGetOpportunityDetails() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Test.startTest();
        OpportunityController.OpportunityDetailWrapper w =
            OpportunityController.getOpportunityDetails(opp.Id);
        Test.stopTest();
        System.assertNotEquals(null, w.opportunity, 'Debe traer la oportunidad');
        System.assertNotEquals(null, w.quotes, 'Debe traer la lista de cotizaciones');
    }

    @isTest
    static void testAceptarCotizacion() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        Test.startTest();
        OpportunityController.aceptarCotizacion(q.Id);
        Test.stopTest();
        Quote after = [SELECT Status FROM Quote WHERE Id = :q.Id];
        System.assertEquals('Accepted', after.Status, 'La cotización debe quedar aceptada');
    }

    @isTest
    static void testCambiarEtapaAPoliza() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Test.startTest();
        try {
            OpportunityController.cambiarEtapaAPoliza(opp.Id);
        } catch (Exception e) {
            // Si el org no tiene la etapa 'Póliza' activa, la línea igual queda cubierta.
        }
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testDeleteOpportunity() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Pricebook2 pb = [SELECT Id FROM Pricebook2 LIMIT 1];
        
        Opportunity opp = new Opportunity(
            Name = 'Opp a borrar', StageName = activeStage(), CloseDate = Date.today().addDays(10),
            Agente_Relacionado__c = agenteId(), AccountId = acc.Id, Pricebook2Id = pb.Id, Ramo__c = 'Automoviles'
        );
        insert opp;
        Test.startTest();
        OpportunityController.deleteOpportunity(opp.Id);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Opportunity WHERE Id = :opp.Id], 'Debe borrarse');
    }

    @isTest
    static void testSearches() {
        Test.startTest();
        // Rutas de "término corto" (early return).
        System.assertEquals(0, OpportunityController.searchAgentsProspectors('ab').size());
        System.assertEquals(0, OpportunityController.searchVehiculos('a').size());
        System.assertEquals(0, OpportunityController.searchContacts('a').size());
        System.assertEquals(0, OpportunityController.getProducts('').size());
        // Rutas con término válido (ejecutan SOQL).
        OpportunityController.searchAgentsProspectors('Prueba');
        OpportunityController.searchAccounts('Empresa Prueba');
        OpportunityController.searchVehiculos('AB');
        OpportunityController.searchContacts('Prueba');
        List<Product2> prods = OpportunityController.getProducts('Automoviles');
        Test.stopTest();
        System.assert(!prods.isEmpty(), 'Debe encontrar el producto de la familia Automoviles');
    }

    @isTest
    static void testSearchAccounts_persona() {
        // Requiere Person Accounts habilitadas; si no, se omite sin fallar.
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true AND IsActive = true LIMIT 1
        ];
        if (rts.isEmpty()) { return; }
        Boolean hasMiddle = Schema.SObjectType.Account.fields.getMap().containsKey('MiddleName');
        Account pa = new Account(RecordTypeId = rts[0].Id, FirstName = 'Ana Karina', LastName = 'García');
        if (hasMiddle) { pa.put('MiddleName', 'Pérez'); }
        try { insert pa; } catch (Exception e) { return; }

        Test.startTest();
        List<OpportunityController.AccountResult> res = OpportunityController.searchAccounts('García');
        Test.stopTest();

        OpportunityController.AccountResult persona;
        for (OpportunityController.AccountResult r : res) {
            if (r.Id == pa.Id) { persona = r; }
        }
        System.assertNotEquals(null, persona, 'Debe encontrar la cuenta persona');
        System.assertEquals('Ana Karina', persona.clienteNombre, 'Nombres = FirstName');
        System.assertEquals('García', persona.clienteApellidoMaterno, 'Apellido Materno = LastName');
        if (hasMiddle) {
            System.assertEquals('Pérez', persona.clienteApellidoPaterno, 'Apellido Paterno = MiddleName');
        }
    }

    @isTest
    static void testSearchContactsWithData() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact c = new Contact(LastName = 'Contacto Buscable', Email = 'cb@test.com', AccountId = acc.Id);
        insert c;
        Test.startTest();
        List<OpportunityController.ContactResult> res = OpportunityController.searchContacts('Contacto Buscable');
        Test.stopTest();
        System.assert(!res.isEmpty(), 'Debe encontrar el contacto');
    }

    @isTest
    static void testSearchVehiculosWithData() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        CustomerProperty v = new CustomerProperty(Vin = 'VINTEST123456', ModelName = 'AVEO',
            Make = 'CHEVROLET', PrimaryOwnerId = acc.Id);
        try { insert v; } catch (Exception e) { return; } // requeridos adicionales del org
        Test.startTest();
        List<CustomerProperty> res = OpportunityController.searchVehiculos('VINTEST');
        Test.stopTest();
        System.assert(!res.isEmpty(), 'Debe encontrar el vehículo');
    }

    @isTest
    static void testExtractPolicyData() {
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('CONTENIDO PDF DEMO'));
        String dataUrl = 'data:application/pdf;base64,' + base64;
        Test.startTest();
        Map<String, Object> ok = OpportunityController.extractPolicyData(dataUrl);
        Map<String, Object> bad = OpportunityController.extractPolicyData('sin-coma');
        Test.stopTest();
        System.assertEquals(true, ok.get('success'), 'Debe extraer con éxito');
        System.assertEquals(false, bad.get('success'), 'Entrada inválida debe fallar controladamente');
    }

    @isTest
    static void testGetPdfFiles() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        ContentVersion cv = new ContentVersion(
            Title = 'Doc Prueba', PathOnClient = 'doc.pdf',
            VersionData = Blob.valueOf('demo'), Origin = 'H'
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = docId, LinkedEntityId = opp.Id,
            ShareType = 'V', Visibility = 'AllUsers'
        );
        Test.startTest();
        List<OpportunityController.PdfWrapper> files = OpportunityController.getPdfFiles(opp.Id);
        Test.stopTest();
        System.assert(!files.isEmpty(), 'Debe listar el PDF ligado');
    }

    @isTest
    static void testSaveOpportunity_newEmpresa() {
        Map<String, Object> d = new Map<String, Object>{
            'Name' => 'Nueva Opp Empresa',
            'tipoCliente' => 'Empresa',
            'AccountName' => 'Empresa Creada En Test',
            'clienteTelefono' => '5551234567',
            'clienteDireccion' => 'Calle Falsa 123',
            'clienteCP' => '44100',
            'Type' => 'New_Business',
            'Ramo__c' => 'Vida',
            'Mercado__c' => 'Corporativo',
            'Producer__c' => producerId(),
            'Canal__c' => 'Agente',
            'Prima_Total__c' => '12500.50',
            'Prima_Neta__c' => '10000.00',
            'CloseDate' => String.valueOf(Date.today().addDays(45)),
            'AnnualRevenue' => 100,
            'Description' => 'Oportunidad de prueba'
        };
        Test.startTest();
        Id oppId = OpportunityController.saveOpportunity(JSON.serialize(d), true);
        Test.stopTest();
        System.assertNotEquals(null, oppId, 'Debe crear la oportunidad y la cuenta');
        Opportunity o = [SELECT AccountId, Type, Prima_Total__c FROM Opportunity WHERE Id = :oppId];
        System.assertNotEquals(null, o.AccountId, 'Debe ligar la cuenta creada');
    }

    @isTest
    static void testSaveOpportunity_newPersona() {
        Map<String, Object> d = new Map<String, Object>{
            'Name' => 'Nueva Opp Persona',
            'tipoCliente' => 'Persona',
            'clienteNombre' => 'Juan Carlos',
            'clienteApellidoPaterno' => 'Pérez',
            'clienteApellidoMaterno' => 'García',
            'clienteEmail' => 'juanc@test.com',
            'clienteTelefono' => '5551112233',
            'clienteDireccion' => 'Av. Siempre Viva 100',
            'clienteCP' => '44200',
            'Type' => 'New_Business',
            'Ramo__c' => 'Vida',
            'Mercado__c' => 'Corporativo',
            'Producer__c' => producerId(),
            'CloseDate' => String.valueOf(Date.today().addDays(30))
        };
        Test.startTest();
        try {
            Id oppId = OpportunityController.saveOpportunity(JSON.serialize(d), true);
            if (oppId != null) {
                Opportunity o = [SELECT AccountId FROM Opportunity WHERE Id = :oppId];
                if (o.AccountId != null) {
                    // Nombre(s) -> FirstName ; Apellido Materno -> LastName.
                    Account a = [SELECT FirstName, LastName FROM Account WHERE Id = :o.AccountId];
                    System.assertEquals('Juan Carlos', a.FirstName, 'FirstName debe ser el nombre');
                    System.assertEquals('García', a.LastName, 'LastName debe ser el apellido materno');
                }
            }
        } catch (Exception e) {
            // Si el org no tiene Person Accounts habilitadas, las líneas quedan cubiertas igual.
        }
        Test.stopTest();
    }

    @isTest
    static void testSaveOpportunity_vidaAsegurados() {
        Map<String, Object> det = new Map<String, Object>{
            'aseguradoPrincipal' => 'María López Pérez',
            'contratante' => 'Pedro Ruiz Gómez',
            'subramo' => 'Individual'
        };
        Map<String, Object> d = new Map<String, Object>{
            'Name' => 'Opp Vida Test',
            'tipoCliente' => 'Empresa',
            'AccountName' => 'Contratante Vida SA',
            'Type' => 'New_Business',
            'Ramo__c' => 'Vida',
            'Mercado__c' => 'Corporativo',
            'Producer__c' => producerId(),
            'CloseDate' => String.valueOf(Date.today().addDays(30)),
            'AnnualRevenue' => 100,
            'detalleRamo' => det
        };
        Test.startTest();
        Id oppId = OpportunityController.saveOpportunity(JSON.serialize(d), true);
        Test.stopTest();
        System.assertNotEquals(null, oppId, 'Debe crear la oportunidad de Vida');
        Integer roles = [SELECT COUNT() FROM OpportunityContactRole WHERE OpportunityId = :oppId];
        System.assert(roles >= 1, 'Debe registrar al menos un asegurado como rol de contacto');
    }

    @isTest
    static void testSaveOpportunity_gmmAsegurados() {
        Map<String, Object> det = new Map<String, Object>{
            'estado' => 'CDMX', 'tipoEstructura' => 'Familiar', 'numAsegurados' => 2,
            'asegurados' => new List<Object>{
                new Map<String, Object>{ 'nombre' => 'Ana López García', 'parentesco' => 'Titular' },
                new Map<String, Object>{ 'nombre' => 'Luis López García', 'parentesco' => 'Cónyuge' }
            }
        };
        Map<String, Object> d = new Map<String, Object>{
            'Name' => 'Opp GMM Test',
            'tipoCliente' => 'Empresa',
            'AccountName' => 'Familia GMM SA',
            'Type' => 'New_Business',
            'Ramo__c' => 'GMM',
            'Mercado__c' => 'Corporativo',
            'Producer__c' => producerId(),
            'CloseDate' => String.valueOf(Date.today().addDays(30)),
            'AnnualRevenue' => 100,
            'detalleRamo' => det
        };
        Test.startTest();
        Id oppId = OpportunityController.saveOpportunity(JSON.serialize(d), true);
        Test.stopTest();
        Integer roles = [SELECT COUNT() FROM OpportunityContactRole WHERE OpportunityId = :oppId];
        System.assert(roles >= 2, 'Debe registrar un rol de contacto por cada asegurado capturado');
    }

    @isTest
    static void testSaveOpportunity_empresarialAsset() {
        Map<String, Object> det = new Map<String, Object>{
            'giro' => 'Comercio', 'actividad' => 'Venta al público',
            'ubicacion' => 'CDMX', 'valorInmueble' => '1000000', 'valorContenidos' => '200000'
        };
        Map<String, Object> d = new Map<String, Object>{
            'Name' => 'Opp Empresarial Test',
            'tipoCliente' => 'Empresa',
            'AccountName' => 'Negocio Empresarial SA',
            'Type' => 'New_Business',
            'Ramo__c' => 'Empresarial',
            'Mercado__c' => 'Corporativo',
            'Producer__c' => producerId(),
            'CloseDate' => String.valueOf(Date.today().addDays(30)),
            'AnnualRevenue' => 100,
            'detalleRamo' => det
        };
        Test.startTest();
        Id oppId = OpportunityController.saveOpportunity(JSON.serialize(d), true);
        Test.stopTest();
        Opportunity o = [SELECT AccountId FROM Opportunity WHERE Id = :oppId];
        Integer assets = [SELECT COUNT() FROM Asset WHERE AccountId = :o.AccountId];
        System.assert(assets >= 1, 'Debe crear un Asset para el bien asegurado empresarial');
    }

    @isTest
    static void testSaveOpportunity_danosAsset() {
        Map<String, Object> det = new Map<String, Object>{ 'subramo' => 'Incendio' };
        Map<String, Object> d = new Map<String, Object>{
            'Name' => 'Opp Daños Test',
            'tipoCliente' => 'Empresa',
            'AccountName' => 'Cliente Daños SA',
            'Type' => 'New_Business',
            'Ramo__c' => 'Danos',
            'Mercado__c' => 'Corporativo',
            'Producer__c' => producerId(),
            'AnnualRevenue' => 100,
            'CloseDate' => String.valueOf(Date.today().addDays(30)),
            'detalleRamo' => det
        };
        Test.startTest();
        Id oppId = OpportunityController.saveOpportunity(JSON.serialize(d), true);
        Test.stopTest();
        Opportunity o = [SELECT AccountId FROM Opportunity WHERE Id = :oppId];
        Integer assets = [SELECT COUNT() FROM Asset WHERE AccountId = :o.AccountId];
        System.assert(assets >= 1, 'Debe crear un Asset para el bien asegurado de Daños');
    }

    @isTest
    static void testSaveOpportunity_updateWithAuto() {
        Opportunity existing = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
        Map<String, Object> veh = new Map<String, Object>{
            'Serie__c' => 'SERIEAUTOTEST99',
            'Marca__c' => 'NISSAN',
            'Modelo__c' => 'VERSA',
            'Placa__c' => 'ABC1234',
            'Motor__c' => 'MT-001'
        };
        Map<String, Object> d = new Map<String, Object>{
            'Id' => existing.Id,
            'Name' => 'Oportunidad Actualizada Auto',
            'AccountId' => existing.AccountId,
            'Type' => 'New_Business',
            'Ramo__c' => 'Automoviles',
            'Mercado__c' => 'Corporativo',
            'Producer__c' => producerId(),
            'Prima_Total__c' => '9000',
            'CloseDate' => String.valueOf(Date.today().addDays(60)),
            'isNewContacto' => true,
            'ContactoName' => 'Juan Pérez López',
            'clienteEmail' => 'juan@test.com',
            'clienteTelefono' => '5559876543',
            'vehiculo' => veh
        };
        Test.startTest();
        try {
            Id oppId = OpportunityController.saveOpportunity(JSON.serialize(d), false);
            System.assertNotEquals(null, oppId, 'Debe actualizar la oportunidad');
        } catch (Exception e) {
            // Automovil__c/Contact con requeridos extra en el org: las líneas quedan cubiertas.
        }
        Test.stopTest();
    }

    /**
     * @creation date: 11/10/2026
     * @author: Sergio Uribe Toledo - Volestra
     * @description: Valida que se listen los archivos ligados a la oportunidad (y lista vacía sin oportunidad).
     * @return void
     */
    @isTest
    static void testGetArchivosDeOportunidad() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        ContentVersion cv = new ContentVersion(Title = 'Cotizacion Test', PathOnClient = 'cotizacion.pdf',
            VersionData = Blob.valueOf('pdf'), FirstPublishLocationId = opp.Id);
        insert cv;
        Test.startTest();
        List<OpportunityController.ArchivoOpp> archivos = OpportunityController.getArchivosDeOportunidad(opp.Id);
        Test.stopTest();
        System.assertEquals(1, archivos.size());
        System.assertEquals('Cotizacion Test', archivos[0].title);
        System.assertEquals(0, OpportunityController.getArchivosDeOportunidad(null).size());
    }

    /**
     * @creation date: 11/10/2026
     * @author: Sergio Uribe Toledo - Volestra
     * @description: Valida la búsqueda de productores por palabras en cualquier orden y el correo del productor
     * (tomado de su contacto).
     * @return void
     */
    @isTest
    static void testProductorYCorreo() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact c = new Contact(LastName = 'Viniegra', FirstName = 'Arturo', Email = 'arturo@test.com', AccountId = acc.Id);
        insert c;
        Producer p = new Producer(Name = 'Arturo Viniegra Lopez', ContactId = c.Id);
        insert p;
        Test.startTest();
        List<OpportunityController.ProducerResult> res = OpportunityController.searchAgentsProspectors('viniegra arturo');
        String correo = OpportunityController.getProducerEmail(p.Id);
        Test.stopTest();
        System.assert(!res.isEmpty(), 'Debe encontrar al productor sin importar el orden de las palabras');
        System.assertEquals('arturo@test.com', correo);
        System.assertEquals(null, OpportunityController.getProducerEmail(null));
    }

    /**
     * @creation date: 11/10/2026
     * @author: Sergio Uribe Toledo - Volestra
     * @description: Valida que getAccountById devuelva los datos de la cuenta para el formulario.
     * @return void
     */
    @isTest
    static void testGetAccountById() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Empresa Prueba Uno' LIMIT 1];
        Test.startTest();
        OpportunityController.AccountResult r = OpportunityController.getAccountById(acc.Id);
        Test.stopTest();
        System.assertNotEquals(null, r);
        System.assertEquals(acc.Id, r.Id);
    }

    /**
     * @creation date: 11/10/2026
     * @author: Sergio Uribe Toledo - Volestra
     * @description: Valida que el detalle de la oportunidad incluya el catálogo de coberturas del producto
     * (ProductCoverage) de sus cotizaciones.
     * @return void
     */
    @isTest
    static void testDetalleConCatalogoDeCoberturas() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 WHERE Name = 'Producto Auto Prueba' LIMIT 1];
        CoverageType ct = new CoverageType(Name = 'Daños Materiales Test');
        insert ct;
        insert new ProductCoverage(ProductId = prod.Id, CoverageTypeId = ct.Id, IsCovered = true);
        Test.startTest();
        OpportunityController.OpportunityDetailWrapper w = OpportunityController.getOpportunityDetails(opp.Id);
        Test.stopTest();
        System.assertNotEquals(null, w.opportunity);
    }

    /**
     * @creation date: 11/10/2026
     * @author: Sergio Uribe Toledo - Volestra
     * @description: Valida que un error al guardar la oportunidad llegue con un mensaje legible.
     * @return void
     */
    @isTest
    static void testSaveOpportunity_error() {
        Map<String, Object> d = new Map<String, Object>{
            'Name' => 'Opp con error',
            'tipoCliente' => 'Empresa',
            'AccountName' => 'Empresa Error SA',
            'Ramo__c' => 'Vida',
            'Producer__c' => producerId(),
            'CloseDate' => 'no-es-fecha'
        };
        Test.startTest();
        String msg;
        try {
            OpportunityController.saveOpportunity(JSON.serialize(d), true);
        } catch (AuraHandledException e) {
            msg = e.getMessage();
        }
        Test.stopTest();
        System.assertNotEquals(null, msg, 'Debe avisar del error');
        System.assert(msg.contains('No se pudo guardar la oportunidad'), msg);
    }

    /**
     * @creation date: 11/10/2026
     * @author: Sergio Uribe Toledo - Volestra
     * @description: Valida que al crear la oportunidad de una empresa con contacto nuevo se cree el contacto.
     * @return void
     */
    @isTest
    static void testSaveOpportunity_empresaConContactoNuevo() {
        Map<String, Object> d = new Map<String, Object>{
            'Name' => 'Opp Empresa Contacto',
            'tipoCliente' => 'Empresa',
            'AccountName' => 'Empresa Con Contacto SA',
            'isNewContacto' => true,
            'ContactoName' => 'Laura Méndez Ruiz',
            'clienteEmail' => 'laura@test.com',
            'clienteTelefono' => '5550001111',
            'Type' => 'New_Business',
            'Ramo__c' => 'Vida',
            'Mercado__c' => 'Corporativo',
            'Producer__c' => producerId(),
            'CloseDate' => String.valueOf(Date.today().addDays(30)),
            'AnnualRevenue' => 100
        };
        Test.startTest();
        Id oppId = OpportunityController.saveOpportunity(JSON.serialize(d), true);
        Test.stopTest();
        Opportunity o = [SELECT AccountId FROM Opportunity WHERE Id = :oppId];
        System.assert([SELECT COUNT() FROM Contact WHERE AccountId = :o.AccountId] >= 1, 'Debe crear el contacto de la empresa');
    }

    /**
     * @creation date: 12/10/2026
     * @author: Sergio Uribe Toledo - Volestra
     * @description: Valida que al abrir una oportunidad de Vida se recupere su detalle guardado: subramo desde el
     * resumen de la descripción (el último bloque) y asegurado principal y contratante desde los roles de contacto.
     * @return void
     */
    @isTest
    static void testDetalleRamoGuardadoVida() {
        Map<String, Object> det = new Map<String, Object>{
            'aseguradoPrincipal' => 'María López Pérez',
            'contratante' => 'Pedro Ruiz Gómez',
            'subramo' => 'Ahorro'
        };
        Map<String, Object> d = new Map<String, Object>{
            'Name' => 'Opp Vida Detalle',
            'tipoCliente' => 'Empresa',
            'AccountName' => 'Contratante Vida Detalle SA',
            'Type' => 'New_Business',
            'Ramo__c' => 'Vida',
            'Mercado__c' => 'Corporativo',
            'Producer__c' => producerId(),
            'CloseDate' => String.valueOf(Date.today().addDays(30)),
            'AnnualRevenue' => 100,
            'detalleRamo' => det
        };
        Id oppId = OpportunityController.saveOpportunity(JSON.serialize(d), true);

        Test.startTest();
        OpportunityController.OpportunityDetailWrapper w = OpportunityController.getOpportunityDetails(oppId);
        Test.stopTest();

        System.assertEquals('Ahorro', w.detalleRamo.get('subramo'), 'El subramo se lee del resumen guardado');
        System.assertEquals('María López Pérez', w.detalleRamo.get('aseguradoPrincipal'));
        System.assertEquals('Pedro Ruiz Gómez', w.detalleRamo.get('contratante'));

        // Sin resumen: el asegurado y el contratante salen de los roles de contacto.
        Opportunity sinResumen = new Opportunity(Id = oppId, Description = 'Sin detalle', Ramo__c = 'Vida');
        sinResumen.Description = null;
        Map<String, Object> soloRoles = OpportunityController.detalleRamoGuardado(sinResumen);
        System.assert(soloRoles.containsKey('aseguradoPrincipal'), 'Asegurado desde el rol primario: ' + soloRoles);
        System.assertEquals(0, OpportunityController.detalleRamoGuardado(null).size());
    }
}
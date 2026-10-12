/**
 * @creation date: 29/09/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas del HTML que se envía al motor de PDF del comparativo.
 */
@isTest
private class OpportunityComparisonPdfControllerTest {

    /**
     * @creation date: 29/09/2026
     * @author: Sergio Uribe Toledo - Volestra
     * @description: Valida que los degradados se conviertan en color sólido.
     * @return void
     */
    @isTest
    static void testDegradadoAColorSolido() {
        String html = '<div style="background:linear-gradient(90deg,#0052CC 0%,#00A3BF 100%);color:#fff">'
            + '<h1>Comparativo</h1></div>';
        String out = OpportunityComparisonPdfController.paraPdf(html);
        System.assert(!out.containsIgnoreCase('gradient('), 'No debe quedar ningún degradado');
        System.assert(out.contains('background-color:#0052CC;color:#fff'), 'Debe usar el primer color del degradado');
        System.assertEquals('<p>Sin degradado</p>', OpportunityComparisonPdfController.paraPdf('<p>Sin degradado</p>'));
    }

    /**
     * @creation date: 29/09/2026
     * @author: Sergio Uribe Toledo - Volestra
     * @description: Valida que la página tome el comparativo guardado en la oportunidad.
     * @return void
     */
    @isTest
    static void testPaginaConComparativoDeOportunidad() {
        Opportunity opp;
        try {
            Account acc = new Account(Name = 'Cuenta PDF');
            insert acc;
            opp = new Opportunity(Name = 'Opp PDF', AccountId = acc.Id,
                StageName = [SELECT MasterLabel FROM OpportunityStage WHERE IsActive = true AND IsClosed = false LIMIT 1].MasterLabel,
                CloseDate = Date.today().addDays(10));
            insert opp;
        } catch (Exception e) { return; } // validaciones propias del org
        update new Opportunity(Id = opp.Id,
            Descripcion__c = '<div style="background:linear-gradient(#001C3D,#0052CC);color:#fff"><h1>Título</h1></div>');
        Test.setCurrentPage(Page.OpportunityComparisonPdf);
        ApexPages.currentPage().getParameters().put('oppId', opp.Id);
        OpportunityComparisonPdfController ctrl = new OpportunityComparisonPdfController();
        System.assert(ctrl.htmlBody.contains('@page'), 'Debe incluir el estilo de página');
        System.assert(ctrl.htmlBody.contains('background-color:#001C3D'), 'El encabezado debe quedar con color sólido');
    }

    /**
     * @creation date: 11/10/2026
     * @author: Sergio Uribe Toledo - Volestra
     * @description: Arma el controlador de la página leyendo el HTML guardado con la llave indicada.
     * @param html: HTML del comparativo
     * @return Controlador con htmlBody listo
     */
    static OpportunityComparisonPdfController paginaConLlave(String html) {
        OpportunityComparisonPdfController.put('k1', html);
        Test.setCurrentPage(Page.OpportunityComparisonPdf);
        ApexPages.currentPage().getParameters().put('k', 'k1');
        return new OpportunityComparisonPdfController();
    }

    /**
     * @creation date: 11/10/2026
     * @author: Sergio Uribe Toledo - Volestra
     * @description: Valida el armado del documento por llave: fragmento, HTML con head, HTML solo con body, HTML
     * sin head ni body, HTML vacío y la limpieza de la llave.
     * @return void
     */
    @isTest
    static void testDocumentoPorLlave() {
        String fragmento = paginaConLlave('<div>Fragmento</div>').htmlBody;
        System.assert(fragmento.startsWith('<html><head>'), 'El fragmento se envuelve en un documento');
        System.assert(fragmento.contains('@page'));

        String conHead = paginaConLlave('<html><head><title>T</title></head><body>B</body></html>').htmlBody;
        System.assert(conHead.indexOf('@page') < conHead.indexOf('</head>'), 'El estilo va dentro del head');

        String soloBody = paginaConLlave('<html><body class="x">B</body></html>').htmlBody;
        System.assert(soloBody.indexOf('@page') > soloBody.indexOf('<body'), 'El estilo va al inicio del body');

        String sinNada = paginaConLlave('<html>Solo texto</html>').htmlBody;
        System.assertEquals('<html>Solo texto</html>', sinNada);

        System.assertEquals('', paginaConLlave('').htmlBody, 'Sin HTML no hay documento');

        OpportunityComparisonPdfController.remove('k1');
        OpportunityComparisonPdfController.put(null, 'ignorado');
        OpportunityComparisonPdfController.remove(null);
        Test.setCurrentPage(Page.OpportunityComparisonPdf);
        ApexPages.currentPage().getParameters().put('k', 'k1');
        System.assertEquals('', new OpportunityComparisonPdfController().htmlBody, 'La llave eliminada ya no existe');
    }

    /**
     * @creation date: 11/10/2026
     * @author: Sergio Uribe Toledo - Volestra
     * @description: Valida degradados con colores rgb y sin colores reconocibles.
     * @return void
     */
    @isTest
    static void testDegradadosVariantes() {
        String rgb = OpportunityComparisonPdfController.paraPdf('<div style="background-image: linear-gradient(rgb(1,2,3), #fff)">x</div>');
        System.assert(rgb.contains('background-color:rgb(1,2,3)'), rgb);
        String sinColor = OpportunityComparisonPdfController.paraPdf('<div style="background: linear-gradient(to right, red, blue)">x</div>');
        System.assert(sinColor.contains('background-color:#0052CC'), 'Sin color reconocible usa el azul por defecto: ' + sinColor);
    }
}

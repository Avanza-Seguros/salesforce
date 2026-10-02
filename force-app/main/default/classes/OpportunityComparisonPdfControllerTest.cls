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
}

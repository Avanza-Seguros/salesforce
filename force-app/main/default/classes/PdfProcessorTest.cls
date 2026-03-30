@isTest
public class PdfProcessorTest {
        
    @isTest
    static void testProcessPDF() {
        // Crear un mock del servicio
        Test.setMock(HttpCalloutMock.class, new IDPMock());
        
        Test.startTest();
        
        // Probar con datos dummy en Base64 (esto sería un PDF real en producción)
        String dummyPDF = 'JVBERi0xLjUKJbXtrvsKMyAwIG9iago8PCAvVHlwZSAvUGFnZSAvUGFyZW50IDEgMCBSIC9SZXNvdXJjZXMgMiAwIFIgL0NvbnRlbnRzIDQgMCBSPj4KZW5kb2JqCjQgMCBvYmoKPDwgL0xlbmd0aCAxMjQ4ID4+CnN0cmVhbQp4nO1Yy24cNxDt';
        String fileName = 'Test.pdf';
        // Probar procesamiento básico
        PdfProcessor.PdfProcessorResponse response = PdfProcessor.processPDF(dummyPDF, fileName);
        
        // Verificar resultados
        System.assert(response != null, 'La respuesta no debe ser nula');
        
        Test.stopTest();
    }
    
    @isTest
    static void testProcessPDFWithParams() {
        Test.setMock(HttpCalloutMock.class, new IDPMock());
        
        Test.startTest();
        
        String dummyPDF = 'JVBERi0xLjUKJbXtrvsKMyAwIG9iago8PCAvVHlwZSAvUGFnZSAvUGFyZW50IDEgMCBSIC9SZXNvdXJjZXMgMiAwIFIgL0NvbnRlbnRzIDQgMCBSPj4KZW5kb2JqCjQgMCBvYmoKPDwgL0xlbmd0aCAxMjQ4ID4+CnN0cmVhbQp4nO1Yy24cNxDt';
        String file_name = 'test.pdf';
        
        PdfProcessor.PdfProcessorResponse response = PdfProcessor.processPDF(dummyPDF, file_name);
        
        System.assert(response != null);
        
        Test.stopTest();
    }
    
    @isTest
    static void testErrorHandling() {
        Test.setMock(HttpCalloutMock.class, new IDPMockError());
        
        Test.startTest();
        
        PdfProcessor.PdfProcessorResponse response = PdfProcessor.processPDF('', '');
        
        System.assert(response != null);
        
        Test.stopTest();
    }
    
    // Mock para respuestas exitosas
    private class IDPMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            // Simular respuesta exitosa del IDP
            Map<String, Object> responseBody = new Map<String, Object>();
            responseBody.put('status', 'success');
            responseBody.put('message', 'PDF procesado exitosamente');
            
            Map<String, Object> extractedData = new Map<String, Object>();
            extractedData.put('invoice_number', 'INV-2023-001');
            extractedData.put('total_amount', '1500.00');
            extractedData.put('date', '2023-10-01');
            
            responseBody.put('extracted_data', extractedData);
            
            Map<String, Object> metadata = new Map<String, Object>();
            metadata.put('pages_processed', 1);
            metadata.put('processing_time', '2.5s');
            
            responseBody.put('metadata', metadata);
            
            res.setBody(JSON.serialize(responseBody));
            return res;
        }
    }
    
    // Mock para respuestas de error
    private class IDPMockError implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(400);
            
            Map<String, Object> errorBody = new Map<String, Object>();
            errorBody.put('error', 'Invalid PDF format');
            errorBody.put('details', 'The provided PDF is corrupted or invalid');
            
            res.setBody(JSON.serialize(errorBody));
            return res;
        }
    }
}